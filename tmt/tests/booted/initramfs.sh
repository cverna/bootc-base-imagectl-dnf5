#!/bin/bash
set -euo pipefail
for kdir in /usr/lib/modules/*/; do
    test -f "$kdir/initramfs.img"
done
bls=$(find /boot -path '*entries*' -name '*.conf' | head -1)
test -n "$bls"
grep -q '^initrd ' "$bls"
