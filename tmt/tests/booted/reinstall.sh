#!/bin/bash
# Reinstall the running (package-mode) system from a derived test image and
# reboot into it. Standard tmt reboot pattern: run 0 stages the reinstall and
# requests a reboot; run 1 verifies we booted the image.
#
# The minimal base image has no sshd, so Testing Farm cannot reconnect after
# the reboot. Derive a test image that only adds openssh-server.
set -euo pipefail
img="${IMAGE:-ghcr.io/cverna/bootc-base-imagectl-dnf5:latest}"
testimg="localhost/bootc-base-imagectl-dnf5-sshd"
here=$(cd "$(dirname "$0")" && pwd)

if [ "${TMT_REBOOT_COUNT:-0}" -eq 0 ]; then
    podman pull "$img"
    podman build -t "$testimg" --build-arg BASE="$img" \
        -f "$TMT_TREE/test-images/openssh/Containerfile" "$TMT_TREE"
    expect "$here/reinstall.exp" "containers-storage:$testimg"
    tmt-reboot
fi

# After the reboot we must be running the image we built.
bootc status >/dev/null
test -f /usr/share/rpm/rpmdb.sqlite
grep -q '^enabled = yes$' /usr/lib/ostree/prepare-root.conf
