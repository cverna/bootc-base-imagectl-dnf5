#!/bin/bash
# Reinstall the running (package-mode) system from the built standard image
# and reboot into it. Standard tmt reboot pattern: run 0 stages the reinstall
# and requests a reboot; run 1 verifies we booted the image.
#
# We test the per-commit image (ghcr.io/...:<sha>-standard, which CI publishes
# as a multi-arch manifest) rather than the floating :standard tag, so we never
# reinstall a stale image published by an earlier push. CI publishes it after
# the build, so wait for it to appear.
#
# The shipped image stays faithful to base-images; a small derived image adds
# the dependencies tmt needs on the guest (rsync to push the test workdir,
# audit for the AVC check).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=ghcr.io/cverna/bootc-base-imagectl-dnf5
testimg="localhost/bootc-base-imagectl-dnf5-tmt"

if [ -n "${IMAGE:-}" ]; then
    img="$IMAGE"
elif [ -n "${TESTING_FARM_GIT_REF:-}" ]; then
    img="$repo:${TESTING_FARM_GIT_REF:0:12}-standard"
else
    img="$repo:standard"
fi

if [ "${TMT_REBOOT_COUNT:-0}" -eq 0 ]; then
    for i in $(seq 1 45); do
        podman pull "$img" && break
        echo "waiting for $img to be published ($i/45)"
        sleep 20
    done
    podman image exists "$img" || { echo "error: $img is not available" >&2; exit 1; }

    podman build -t "$testimg" --build-arg BASE="$img" \
        -f "$TMT_TREE/test-images/tmt/Containerfile" "$TMT_TREE"
    expect "$here/reinstall.exp" "containers-storage:$testimg"
    tmt-reboot
fi

# After the reboot we must be running the image we built.
bootc status >/dev/null
test -f /usr/share/rpm/rpmdb.sqlite
grep -q '^enabled = yes$' /usr/lib/ostree/prepare-root.conf
