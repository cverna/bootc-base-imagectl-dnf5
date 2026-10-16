#!/bin/bash
set -euo pipefail
# On the booted system the rpmdb lives at the ostree location with the compat
# symlink, and rpm can read it. (Transient sqlite -shm/-wal sidecars are an
# image-build property, checked by the rootfs test against the shipped image;
# the deployed image here is a derived test image that dnf has touched.)
test -f /usr/share/rpm/rpmdb.sqlite
test "$(readlink /usr/lib/sysimage/rpm)" = "../../share/rpm"
rpm -q bootc >/dev/null
