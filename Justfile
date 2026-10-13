# Development entry point for the bootc-base-imagectl-dnf5 proof of concept.
# Run `just --list` for the available targets.

builder := env("BUILDER", "podman")
image := "localhost/bootc-base-imagectl-dnf5"
# Required for the nested containerization (bwrap) the compose uses.
priv := "--security-opt=label=disable --cap-add=all"
version := env("IMAGE_VERSION", "devel")

default: build

# Build the bootc image using dnf5 (no rpm-ostree anywhere).
[group('core')]
build:
    {{builder}} build {{priv}} \
        --build-arg=IMAGE_VERSION={{version}} -t {{image}} .

# Run the bootc container linter against the built image.
[group('core')]
lint:
    {{builder}} run --rm --entrypoint bootc {{image}} container lint

# Rootfs sanity tests: build a test container from the image; the cases in
# tests/rootfs/cases run at build time against the image under test.
[group('core')]
test: build
    {{builder}} build --from {{image}} -f tests/rootfs/Dockerfile \
        -t {{image}}-test tests/rootfs

# Build the guest image used by the tmt container plan.
[group('test')]
tmt-guest:
    {{builder}} build -f tmt/Containerfile.guest \
        --build-arg BASE={{image}}:latest -t {{image}}-tmt .

# Install to a loop device and validate the deployment (needs root).
[group('disk')]
disk-test:
    #!/usr/bin/env bash
    set -euo pipefail
    # The image is in the user's (rootless) storage; the test runs as root.
    {{builder}} save --format=oci-archive -o /var/tmp/{{replace(image, "/", "-")}}-test.oci.tar {{image}}
    sudo {{builder}} load -i /var/tmp/{{replace(image, "/", "-")}}-test.oci.tar
    rm -f /var/tmp/{{replace(image, "/", "-")}}-test.oci.tar
    sudo tests/disk/run {{image}}

# Prove the image installs to a disk and produce raw + qcow2 artifacts.
# Needs root (block device access) and a free loop device.
[group('disk')]
disk name="bootc-base-imagectl-dnf5":
    #!/usr/bin/env bash
    set -euo pipefail
    out="/var/tmp/{{name}}.raw"
    # The image is built in the user's (rootless) storage; the install runs
    # as root, so copy it into root's storage first.
    {{builder}} save --format=oci-archive -o "/var/tmp/{{name}}.oci.tar" {{image}}
    sudo {{builder}} load -i "/var/tmp/{{name}}.oci.tar"
    rm -f "/var/tmp/{{name}}.oci.tar" "$out"
    truncate -s 8G "$out"
    loop=$(sudo losetup -P --find --show "$out")
    trap 'sudo losetup -D' EXIT
    sudo {{builder}} run --rm --privileged --pid=host --security-opt label=disable \
        -v /dev:/dev \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{image}} \
        bootc install to-disk --wipe --filesystem xfs \
            --karg=console=tty0 --karg=console=hvc0 \
            --source-imgref containers-storage:{{image}} \
            --target-transport containers-storage --target-imgref {{image}} \
            "$loop"
    qemu-img convert -O qcow2 "$out" "/var/tmp/{{name}}.qcow2"
    echo "Wrote /var/tmp/{{name}}.raw and /var/tmp/{{name}}.qcow2"
