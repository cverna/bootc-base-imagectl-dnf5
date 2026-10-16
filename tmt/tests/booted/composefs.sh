#!/bin/bash
# The image declares the composefs backend (prepare-root.conf) and the booted
# deployment must actually use it.
#
# Our images use the ostree+composefs model (like base-images): the deployment
# carries a composefs image (.ostree.cfs) and the initramfs mounts it. bootc's
# `status.booted.composefs` field is only set for the newer composefs-native
# backend, so we detect the ostree+composefs model directly.
set -euo pipefail
echo "backend diagnostics:"
findmnt -no FSTYPE,SOURCE / || true
ls -l /ostree/deploy/*/deploy/*.0/.ostree.cfs 2>&1 || true
bootc status --json | jq -c '.status.booted.composefs' 2>&1 || true
echo "assertions:"
grep -q '^enabled = yes$' /usr/lib/ostree/prepare-root.conf
ls /ostree/deploy/*/deploy/*.0/.ostree.cfs >/dev/null
