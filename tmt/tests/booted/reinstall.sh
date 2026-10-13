#!/bin/bash
# Reinstall the running (package-mode) system from the built standard image
# and reboot into it. Standard tmt reboot pattern: run 0 stages the reinstall
# and requests a reboot; run 1 verifies we booted the image.
#
# The standard tier ships sshd + NetworkManager, so Testing Farm can
# reconnect after the reboot; no derived test image is needed.
set -euo pipefail
img="${IMAGE:-ghcr.io/cverna/bootc-base-imagectl-dnf5:standard}"
here=$(cd "$(dirname "$0")" && pwd)

if [ "${TMT_REBOOT_COUNT:-0}" -eq 0 ]; then
    podman pull "$img"
    expect "$here/reinstall.exp" "containers-storage:$img"
    tmt-reboot
fi

# After the reboot we must be running the image we built.
bootc status >/dev/null
test -f /usr/share/rpm/rpmdb.sqlite
grep -q '^enabled = yes$' /usr/lib/ostree/prepare-root.conf
