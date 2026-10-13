#!/bin/bash
# Standard tmt reboot pattern: on the first run, reinstall the running
# system from our image and reboot; on the second run, verify we booted it.
set -euo pipefail
img="${IMAGE:-ghcr.io/cverna/bootc-base-imagectl-dnf5:latest}"

if [ "${TMT_REBOOT_COUNT:-0}" -eq 0 ]; then
    podman pull "$img"
    system-reinstall-bootc --transport containers-storage "$img"
    tmt-reboot
fi

# After reboot: the running system must be our image.
bootc status
bootc status --json | jq -e '.status.booted.image.image.image' >/dev/null
