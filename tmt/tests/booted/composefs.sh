#!/bin/bash
# The image declares the composefs backend (prepare-root.conf) and the booted
# deployment must actually use it, like the rpm-ostree images. bootc reports
# the backend in `status.booted.composefs` (the same check bootc's own tests
# use).
set -euo pipefail
grep -q '^enabled = yes$' /usr/lib/ostree/prepare-root.conf
bootc status --json | jq -e '.status.booted.composefs' >/dev/null
