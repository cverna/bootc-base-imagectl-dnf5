#!/bin/bash
set -euo pipefail
# The booted image should have no failed units. bootc's reinstall cleanup of
# the previous OS (bootc-destructive-cleanup) is a harness artifact - it
# operates on the old root under /sysroot - not a property of this image.
ignore='bootc-destructive-cleanup.service'
failed=$(systemctl --failed --no-legend --no-pager --plain | awk '{print $1}' \
    | grep -vx "$ignore" || true)
if [ -n "$failed" ]; then
    echo "failed systemd units:" >&2
    echo "$failed" >&2
    exit 1
fi
