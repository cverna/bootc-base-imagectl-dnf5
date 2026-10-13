#!/bin/bash
# Reinstall the running (package-mode) system from the image under test.
# Run from the plan's prepare step; the reboot is done afterwards by
# tmt/reboot.yml (tmt-reboot/reboot do not work in prepare).
#
# We test the per-commit image (ghcr.io/...:<sha>-standard, which CI publishes
# as a multi-arch manifest) rather than the floating :standard tag, so we never
# reinstall a stale image published by an earlier push. CI publishes it after
# the build, so wait for it to appear.
#
# The shipped image stays faithful to base-images; a small derived image adds
# what the harness needs on the guest (rsync + audit) and bakes in the tmt
# workdir under /var/ARTIFACTS, because a reinstall replaces /var.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/.." && pwd)
repo=ghcr.io/cverna/bootc-base-imagectl-dnf5
testimg=localhost/bootc-base-imagectl-dnf5-tmt

if [ -n "${IMAGE:-}" ]; then
    img="$IMAGE"
elif [ -n "${TESTING_FARM_GIT_REF:-}" ]; then
    img="$repo:${TESTING_FARM_GIT_REF:0:12}-standard"
else
    img="$repo:standard"
fi

for i in $(seq 1 45); do
    podman pull "$img" && break
    echo "waiting for $img to be published ($i/45)"
    sleep 20
done
podman image exists "$img" || { echo "error: $img is not available" >&2; exit 1; }

builddir=$(mktemp -d)
trap 'rm -rf "$builddir"' EXIT
cp "$tree/test-images/tmt/Containerfile" "$builddir/Containerfile"
cp -a /var/ARTIFACTS "$builddir/ARTIFACTS"
podman build -t "$testimg" --build-arg BASE="$img" \
    -f "$builddir/Containerfile" "$builddir"
expect "$here/reinstall.exp" "containers-storage:$testimg"
