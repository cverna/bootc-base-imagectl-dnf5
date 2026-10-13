#!/bin/bash
# The reinstall happens in the plan's prepare step; by the time the tests run
# we must be booted into the image we installed.
set -euo pipefail
bootc status >/dev/null
test -f /usr/share/rpm/rpmdb.sqlite
grep -q '^enabled = yes$' /usr/lib/ostree/prepare-root.conf
