# Development entry point for the bootc-base-imagectl-dnf5 proof of concept.
# Run `just --list` for the available targets.

builder := env("BUILDER", "podman")
# Content tier: standard (default) or minimal. These map onto the vendored
# base-images manifests (manifests/<tier>.yaml).
tier := env("TIER", "standard")
image := "localhost/bootc-base-imagectl-dnf5"
tag := image + ":" + tier
# Required for the nested containerization (bwrap) the compose uses.
priv := "--security-opt=label=disable --cap-add=all"
version := env("IMAGE_VERSION", "devel")

default: build

# Build the image for {{tier}} using dnf5 (no rpm-ostree anywhere).
[group('core')]
build:
    {{builder}} build {{priv}} \
        --build-arg=MANIFEST={{tier}} \
        --build-arg=IMAGE_VERSION={{version}} -t {{tag}} .

# Run the bootc container linter against the built image.
[group('core')]
lint:
    {{builder}} run --rm --entrypoint bootc {{tag}} container lint

# Rootfs sanity tests: build a test container from the image; the cases in
# tests/rootfs/cases run at build time against the image under test.
[group('core')]
test: build
    {{builder}} build --from {{tag}} --build-arg=TIER={{tier}} \
        -f tests/rootfs/Dockerfile -t {{tag}}-test tests/rootfs

# Build the guest image used by the tmt container plan.
[group('test')]
tmt-guest:
    {{builder}} build -f tmt/Containerfile.guest \
        --build-arg BASE={{tag}} -t {{image}}-tmt .

# Build the derived image used by the tmt VM plan (adds tmt's own guest deps).
# The real build (in the plan) also bakes the tmt workdir in via ARTIFACTS.
[group('test')]
test-image: build
    #!/usr/bin/env bash
    set -euo pipefail
    ctx=$(mktemp -d)
    trap 'rm -rf "$ctx"' EXIT
    mkdir -p "$ctx/ARTIFACTS"
    cp test-images/tmt/Containerfile "$ctx/Containerfile"
    {{builder}} build -f "$ctx/Containerfile" --build-arg BASE={{tag}} \
        -t {{image}}-tmt-test "$ctx"

# Install to a loop device and validate the deployment (needs root).
[group('disk')]
disk-test:
    #!/usr/bin/env bash
    set -euo pipefail
    # The image is in the user's (rootless) storage; the test runs as root.
    {{builder}} save --format=oci-archive -o /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-test.oci.tar {{tag}}
    sudo {{builder}} load -i /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-test.oci.tar
    rm -f /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-test.oci.tar
    sudo tests/disk/run {{tag}}

# Install with the composefs backend (`--composefs-backend`) and validate the
# composefs-native layout (needs root).
[group('disk')]
composefs-test:
    #!/usr/bin/env bash
    set -euo pipefail
    {{builder}} save --format=oci-archive -o /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-cfs.oci.tar {{tag}}
    sudo {{builder}} load -i /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-cfs.oci.tar
    rm -f /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-cfs.oci.tar
    sudo tests/disk/run {{tag}} composefs

# Install to a LUKS-encrypted root with `bootc install to-filesystem` and
# validate the deployment (needs root).
[group('disk')]
luks-test:
    #!/usr/bin/env bash
    set -euo pipefail
    {{builder}} save --format=oci-archive -o /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-luks.oci.tar {{tag}}
    sudo {{builder}} load -i /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-luks.oci.tar
    rm -f /var/tmp/{{replace(image, "/", "-")}}-{{tier}}-luks.oci.tar
    sudo tests/disk/luks {{tag}}

# Prove the image installs to a disk and produce raw + qcow2 artifacts.
# Needs root (block device access) and a free loop device.
[group('disk')]
disk name="bootc-base-imagectl-dnf5":
    #!/usr/bin/env bash
    set -euo pipefail
    out="/var/tmp/{{name}}.raw"
    # The image is built in the user's (rootless) storage; the install runs
    # as root, so copy it into root's storage first.
    {{builder}} save --format=oci-archive -o "/var/tmp/{{name}}.oci.tar" {{tag}}
    sudo {{builder}} load -i "/var/tmp/{{name}}.oci.tar"
    rm -f "/var/tmp/{{name}}.oci.tar" "$out"
    truncate -s 8G "$out"
    loop=$(sudo losetup -P --find --show "$out")
    trap 'sudo losetup -D' EXIT
    sudo {{builder}} run --rm --privileged --pid=host --security-opt label=disable \
        -v /dev:/dev \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{tag}} \
        bootc install to-disk --wipe --filesystem xfs \
            --karg=console=tty0 --karg=console=hvc0 \
            --source-imgref containers-storage:{{tag}} \
            --target-transport containers-storage --target-imgref {{tag}} \
            "$loop"
    qemu-img convert -O qcow2 "$out" "/var/tmp/{{name}}.qcow2"
    echo "Wrote /var/tmp/{{name}}.raw and /var/tmp/{{name}}.qcow2"
