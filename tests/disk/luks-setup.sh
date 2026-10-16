#!/bin/bash
# Runs inside a privileged container from the image (which ships
# cryptsetup/dosfstools/xfsprogs). Creates a LUKS-encrypted root on $LOOP
# (a loop device set up by the host driver) and installs the image into it
# with `bootc install to-filesystem`.
#
# Layout: ESP (vfat) + /boot (ext4) + LUKS(root, xfs). A separate non-vfat
# /boot is required because GRUB cannot read a LUKS root, and bootc rejects a
# vfat /boot.
set -euo pipefail
img=${1:?usage: luks-setup.sh <image-ref>}
loop=${LOOP:?LOOP must be set}
pass=testpass

mkfs.fat -n EFI-SYSTEM "${loop}p1"
mkfs.ext4 -q -L boot "${loop}p2"
printf '%s' "$pass" | cryptsetup luksFormat --type luks2 --batch-mode "${loop}p3" -
printf '%s' "$pass" | cryptsetup open "${loop}p3" cryptroot -
mkfs.xfs -f -q /dev/mapper/cryptroot

mkdir -p /target
mount /dev/mapper/cryptroot /target
mkdir -p /target/boot
mount "${loop}p2" /target/boot
mkdir -p /target/efi
mount "${loop}p1" /target/efi

boot_uuid=$(blkid -s UUID -o value "${loop}p2")
luks_uuid=$(cryptsetup luksUUID "${loop}p3")

# --disable-selinux: the container cannot set security.selinux xattrs on the
# target, and this test is about the LUKS install, not SELinux labeling.
bootc install to-filesystem \
    --source-imgref "containers-storage:$img" \
    --target-transport containers-storage --target-imgref "$img" \
    --root-mount-spec "UUID=$luks_uuid" \
    --boot-mount-spec "UUID=$boot_uuid" \
    --karg "rd.luks.uuid=luks-$luks_uuid" \
    --karg=console=tty0 --karg=console=hvc0 \
    --disable-selinux \
    /target

echo "=== validate ==="
# The root partition is LUKS.
cryptsetup isLuks "${loop}p3"

# The ostree deployment landed inside the LUKS root.
test -d /target/ostree/deploy
find /target/ostree/deploy -path '*/usr/share/rpm/rpmdb.sqlite' | grep -q . \
    || { echo "no deployment rpmdb under the LUKS root" >&2; exit 1; }

# The BLS entry (on the separate /boot) points at the LUKS root and carries
# the unlock karg.
bls=$(find /target/boot -path '*entries*' -name '*.conf' | head -1)
test -n "$bls" || { echo "no BLS entry found" >&2; exit 1; }
grep -q "root=UUID=$luks_uuid" "$bls"
grep -q "boot=UUID=$boot_uuid" "$bls"
grep -q "rd.luks.uuid=luks-$luks_uuid" "$bls"
grep -q '^initrd ' "$bls"

echo "luks disk test passed"
