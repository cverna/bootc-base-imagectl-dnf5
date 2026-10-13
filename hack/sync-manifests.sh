#!/bin/bash
# Refresh manifests/ from fedora/bootc/base-images.
#
# Only the manifests needed for the minimal and standard tiers are vendored
# (plus the generic Fedora include). The upstream commit is recorded in
# manifests/UPSTREAM.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --depth=1 https://gitlab.com/fedora/bootc/base-images "$tmp/base-images"
src="$tmp/base-images"
dst="$repo_root/manifests"

rm -rf "$dst"
mkdir -p "$dst"
cp -a "$src/COPYING" "$dst/"
for f in minimal.yaml standard.yaml minimal-plus.hidden.yaml; do
    cp -a "$src/$f" "$dst/"
done
cp -a "$src/fedora-includes" "$dst/"
# ELN is rawhide-only and not built here.
rm -f "$dst/fedora-includes/eln.yaml"
cp -a "$src/minimal" "$src/minimal-plus" "$src/standard" "$dst/"
chmod -R u+rwX,go+rX "$dst"

git -C "$src" rev-parse HEAD > "$dst/UPSTREAM"
echo "synced manifests from fedora/bootc/base-images $(cat "$dst/UPSTREAM")"
