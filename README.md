# bootc-base-imagectl-dnf5

A minimal proof of concept for building **Fedora bootc base images with
`dnf5` instead of `rpm-ostree`**.

Fedora's base images are currently composed with `rpm-ostree compose rootfs`
driven by treefile manifests (see [fedora/bootc/base-images]). With
`rpm-ostree` slated to be dropped from CentOS Stream / RHEL 11 and Fedora,
this prototype explores the replacement path: use `dnf5 --installroot` to
compose the root filesystem, then apply the (small) amount of glue a bootc
image actually needs, and validate the result with `bootc container lint`.

This is intentionally **dnf5-only**: there is no rpm-ostree code path.

## How it works

`bootc-base-imagectl build-rootfs manifest.json TARGET`:

1. seeds the installroot's dnf config (repos, GPG keys, `releasever`) from a
   source root, since `dnf5 --installroot` reads its configuration from the
   installroot;
2. installs the package set with `dnf5 install --installroot` (weak deps and
   docs disabled per the manifest, plus `--exclude`);
3. applies the bootc glue, laid out the way the rpm-ostree-built Fedora
   images are:
   - `systemd-sysusers` for system users, then `systemctl preset-all`;
   - `/var` compatibility (`/var/run`, `/var/tmp` 1777, `/var/lib/rpm-state`);
   - empty `/etc/machine-id`, `/sysroot`, `ostree -> sysroot/ostree`;
   - `/boot` emptied and EFI binaries staged in `/usr/lib/ostree-boot` (a
     non-empty `/boot` makes systemd's gpt-auto-generator target `/efi`);
   - bootupd update metadata (`bootupctl backend generate-update-metadata`);
   - `dracut --add ostree` initramfs per installed kernel;
   - rpmdb relocated to `/usr/share/rpm` with the compat symlinks and the
     `%_dbpath` macro;
   - runtime/log/dnf state removed;
4. runs `bootc container lint`.

Users are kept inline in `/etc` (`passwd: files systemd`), following the
pending "Switch away from nss-altfiles" Change
(<https://github.com/coreos/fedora-coreos-tracker/issues/1599>) rather than
reproducing the legacy `/usr/lib/passwd` split.

## Usage

```bash
just build                  # podman build -> localhost/bootc-base-imagectl-dnf5
just test                   # bootc container lint
just disk                   # bootc install to a loop device -> raw + qcow2 (root)
```

`just build` needs nested-container privileges (`--security-opt=label=disable
--cap-add=all`), which the recipe adds.

### Booting the disk (Apple silicon, vfkit)

```bash
just disk
vfkit --cpus 4 --memory 4096 \
  --bootloader efi,variable-store=efi.fd,create \
  --device virtio-blk,path=/var/tmp/bootc-base-imagectl-dnf5.raw \
  --device virtio-net,nat --device virtio-rng \
  --device virtio-serial,stdio
```

The image has no local user or unlocked root by default; derive an image
that creates one (install `shadow-utils`, `useradd`, `chpasswd`) or inject
credentials in the usual bootc way.

## Status

Working: compose, `bootc container lint`, install to disk, and boot under
Apple Virtualization and qemu (xfs root via the generated initramfs, SELinux
enforcing, PAM login) — behavior matching the rpm-ostree-built minimal image.

Not yet handled (deliberately out of scope for the PoC):

- treefile semantics (includes, per-arch lists, `remove-from-packages`) —
  the manifest here is a flat JSON list;
- byte-reproducible rpmdb (`INSTALLTIME`/`INSTALLTID` normalization);
- SELinux policy recompilation (contexts are applied at deployment);
- cross-architecture and cross-version builds, chunked/layered output.

Known upstream issues observed while booting:

- `bootupctl` aborts on a null image version (`.bootc-aleph.json`); set
  `org.opencontainers.image.version` on the image (as CI does);
- `dracut-crypt-generator` exits 2 when `cryptsetup` is absent (affects the
  rpm-ostree-built minimal image too).

[fedora/bootc/base-images]: https://gitlab.com/fedora/bootc/base-images

## CI

`.github/workflows/build.yml` builds the image for **amd64 and arm64** on
native GitHub-hosted runners (`ubuntu-latest` and `ubuntu-24.04-arm`), runs
`bootc container lint`, and on pushes to `main` (and tags) publishes to GHCR:

    ghcr.io/cverna/bootc-base-imagectl-dnf5:latest          # multi-arch manifest
    ghcr.io/cverna/bootc-base-imagectl-dnf5:<short-sha>     # multi-arch manifest
    ghcr.io/cverna/bootc-base-imagectl-dnf5:<sha>-amd64     # per-arch
    ghcr.io/cverna/bootc-base-imagectl-dnf5:<sha>-arm64     # per-arch

Notes:

- arm64 is built on a **native arm64 runner**, not with QEMU emulation: the
  compose runs package tooling through `bubblewrap`, and `bwrap` cannot
  create namespaces under qemu-user (`Creating new namespace failed:
  Invalid argument`). `bootc-base-imagectl` detects an unusable `bwrap` and
  fails early rather than producing a broken image. (Same limitation as
  <https://gitlab.com/fedora/bootc/base-images/-/issues/57>.)
- GHCR packages created from a workflow token are **private by default**;
  change the package visibility in the repository/package settings if you
  want it public.
- Disk creation and boot tests need loop devices/KVM and are intentionally
  not part of CI.

## License

MIT. See [LICENSE](LICENSE).
