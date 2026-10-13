#!/bin/bash
set -euo pipefail
test -f /usr/share/rpm/rpmdb.sqlite
test '!' -e /usr/share/rpm/rpmdb.sqlite-shm
rpm -q bootc >/dev/null
