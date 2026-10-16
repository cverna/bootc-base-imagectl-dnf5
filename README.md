# bootc-base-imagectl-dnf5

A proof of concept for building **Fedora bootc base images with `dnf5`
instead of `rpm-ostree`**.

Fedora's base images are currently composed with `rpm-ostree compose rootfs`
driven by treefile manifests (see [fedora/bootc/base-images]). With
`rpm-ostree` slated to be dropped from CentOS Stream / RHEL 11 and Fedora,
this prototype explores the replacement path: resolve the *same* manifests,
use `dnf5 --installroot` to compose the root filesystem, apply the (small)
amount of glue a bootc image actually needs, and validate the result with
`bootc container lint`.

This is intentionally **dnf5-only**: there is no rpm-ostree code path.

## Tiers

The base-images content tiers are vendored under `manifests/` and consumed
verbatim, so the package sets and postprocessing match upstream:

| tier       | manifest                  | packages | notes |
|------------|---------------------------|----------|-------|
| `minimal`  | `manifests/minimal.yaml`  | ~22 (+deps) | bootc, systemd, kernel, dnf; no sshd, no NetworkManager |
| `standard` | `manifests/standard.yaml` | ~97 (+deps) | minimal-plus + networking tools, system config, full initramfs; **sshd + NetworkManager** |

`standard` is the tier the VM (tmt/Testing Farm) tests run against, because
it is reachable after a reinstall. `latest` tracks `standard`.

## How it works

`bootc-base-imagectl build-rootfs MANIFEST TARGET`:

1. **resolves** the manifest, a YAML treefile with `include` /
   `conditional-include` / `variables` / `packages[-<arch>]` /
   `exclude-packages[-<arch>]` / `remove-from-packages` / `add-files` /
   `postprocess` / `recommends` / `container-cmd`;
2. seeds the installroot's dnf config (repos, GPG keys, `releasever`) from a
   source root, since `dnf5 --installroot` reads its configuration from the
   installroot;
3. installs the package set with `dnf5 install --installroot` (weak deps and
   docs per `recommends`/`documentation`, plus `--exclude`);
4. applies `add-files` and `remove-from-packages` (files matched by regex,
   restricted to files owned by the named package);
5. runs `systemd-sysusers` for system users;
6. stages the bootloader: `/boot` emptied and EFI binaries moved to
   `/usr/lib/ostree-boot` (`boot-location: modules`; a non-empty `/boot`
   makes systemd's gpt-auto-generator target `/efi`);
7. runs the manifest `postprocess` scripts in rpm-ostree's order (reverse
   include order, preserving order within a file) — these set up
   `prepare-root.conf`, bootupd metadata, kernel-install/dnf config, dracut
   config, systemd presets, tmpfiles, and so on;
8. finalizes the rootfs: the writable top-level paths become symlinks into
   `/var` (`/home`, `/mnt`, `/srv`, `/root`) and `/run/media` (`/media`), like
   the rpm-ostree images, and `/var` is reset to the minimal set (package
   `/var` content is recreated at boot by tmpfiles.d, declared in
   `/usr/lib/tmpfiles.d/bootc-base-imagectl.conf`); plus empty
   `/etc/machine-id`, `/sysroot`, `ostree -> sysroot/ostree`, and runtime
   state removed;
9. generates the initramfs with `dracut`, relocates the rpmdb to
   `/usr/share/rpm` with the compat symlinks and `%_dbpath` macro;
10. runs `bootc container lint`.

### Manifest resolver

`bootc-base-imagectl resolve MANIFEST` prints the fully resolved manifest as
JSON. Its output was validated to be identical to
`rpm-ostree compose tree --print-only` for both tiers: same package set,
excludes, `remove-from-packages`, `add-files`, and identical `postprocess`
ordering.

### Divergence: passwd model

Users are kept inline in `/etc` (`passwd: files systemd`), following the
pending "Switch away from nss-altfiles" Change
(<https://github.com/coreos/fedora-coreos-tracker/issues/1599>) rather than
reproducing the legacy `/usr/lib/passwd` split. The manifests' `nss-altfiles`
package is still installed and `check-passwd`/`check-groups` are not enforced.

## Usage

```bash
just tier=minimal build      # -> localhost/bootc-base-imagectl-dnf5:minimal
just tier=standard build     # -> localhost/bootc-base-imagectl-dnf5:standard
just tier=standard lint      # bootc container lint
just tier=standard test      # rootfs sanity cases against the image
just tier=standard disk      # bootc install to a loop device -> raw + qcow2 (root)
```

`just build` needs nested-container privileges (`--security-opt=label=disable
--cap-add=all`), which the recipe adds.

### Booting the disk (Apple silicon, vfkit)

```bash
just tier=standard disk
vfkit --cpus 4 --memory 4096 \
  --bootloader efi,variable-store=efi.fd,create \
  --device virtio-blk,path=/var/tmp/bootc-base-imagectl-dnf5.raw \
  --device virtio-net,nat --device virtio-rng \
  --device virtio-serial,stdio
```

The minimal image has no local user or unlocked root by default; derive an
image that creates one (install `shadow-utils`, `useradd`, `chpasswd`) or
inject credentials in the usual bootc way. The standard image ships `sshd`.

## Status

Working: manifest resolution, compose, `bootc container lint`, rootfs tests,
install to disk, and boot under Apple Virtualization and qemu (xfs root via
the generated initramfs, SELinux enforcing, PAM login) for both tiers.

Not yet handled (deliberately out of scope for the PoC):

- `check-passwd`/`check-groups` enforcement and the nss-altfiles passwd split
  (see above);
- the manifests' `finalize.d` scripts: we reproduce the outcome of
  `minimal/finalize.d/01-var.sh` in `reset_var` but do not run the scripts
  themselves;
- byte-reproducible rpmdb (`INSTALLTIME`/`INSTALLTID` normalization);
- SELinux policy recompilation (contexts are applied at deployment);
- cross-architecture and cross-version builds, chunked/layered output
  (`rechunk` / chunkah).

Known upstream issues observed while booting:

- `bootupctl` aborts on a null image version (`.bootc-aleph.json`); set
  `org.opencontainers.image.version` on the image (as CI does);
- `dracut-crypt-generator` exits 2 when `cryptsetup` is absent (affects the
  rpm-ostree-built minimal image too).

[fedora/bootc/base-images]: https://gitlab.com/fedora/bootc/base-images

## Tests

`just lint` runs `bootc container lint` against the image.

`just test` builds a container *from* the image and runs the read-only rootfs
sanity cases in `tests/rootfs/cases`, several ported from
[fedora-coreos-config] and [fedora/bootc/base-images]. The `TIER` build arg
lets tier-specific cases (e.g. the `setuid-allowlist`) assert the right set:

- `fedora-only`, `root-mode`, `etc-group`, `users-groups`, `no-iptables-legacy`
- account databases: `etc-permissions`, `gshadow` (parser regression)
- rpmdb: `rpmdb`, `rpmdb-sqlite`, `rpmdb-layout`
- boot/ostree: `initramfs`, `boot-empty`, `bootupd`, `ostree-layout`,
  `composefs`
- system: `systemd-firstboot`, `var`, `var-links`, `yum-repo-dir`,
  `check-symlink`, `nsswitch-inline`
- security: `setuid-allowlist`, `file-permissions`
- encryption: `luks` (the standard tier ships the LUKS tooling)

`just disk-test` (needs root) installs the image to a loop device with
`bootc install to-disk --generic-image` (installs all bootloader types
and skips system-firmware changes, so it works on CI runners) and validates
the resulting deployment: ESP + root partitions,
`/usr/lib/modules/*/initramfs.img`, the BLS entry's `initrd`, the rpmdb
layout, and (when the host enforces SELinux) the on-disk file contexts.

`just luks-test` (needs root) installs the image onto a LUKS-encrypted root
with `bootc install to-filesystem` — the way bootc recommends for encrypted
installs — and validates it: a LUKS root partition, the ostree deployment
inside it, and a BLS entry pointing at the LUKS root with the unlock karg.
The rootfs case `luks` checks the standard tier ships the tooling
(`cryptsetup`, `clevis`, `clevis-pin-tpm2`) and a crypt-capable initramfs.

`just composefs-test` (needs root) installs the image with the **composefs
backend** (`bootc install --composefs-backend`) and validates the
composefs-native layout (`/composefs`, `/state/deploy`, no `/ostree/deploy`)
and the `composefs=` boot argument. Our images use the ostree+composefs model
(they ship `prepare-root.conf`), so the backend is selected explicitly — the
newer composefs-native image detection (`/usr/lib/composefs/setup-root-conf.toml`
with no `prepare-root.conf`) needs a newer bootc than the one in the image.

CI runs `lint`, the rootfs tests, and the disk tests (plus the LUKS install
and composefs-backend tests for the standard tier) on each architecture.

[fedora-coreos-config]: https://github.com/coreos/fedora-coreos-config/tree/main/tests/kola

## tmt integration tests

The repository ships [tmt] metadata under `.fmf/` and `tmt/`, following the
same shape as bootc's own integration tests.

### Container plan (anywhere)

`tmt/plans/rootfs.fmf` runs the rootfs sanity cases *inside* the image using
tmt's container provisioner:

```bash
just tier=standard tmt-guest     # derive the long-running guest image
tmt run -a plan -n rootfs
```

(The guest image exists only because the bootc image runs systemd as PID1,
which tmt's container provisioner cannot keep alive; `tmt/Containerfile.guest`
just overrides `CMD`.)

### VM plan (needs KVM / Testing Farm)

`tmt/plans/booted.fmf` provisions a Fedora cloud VM, reinstalls it from the
built **standard** image and reboots it **in the prepare step** (a reinstall
replaces `/var`, so the tests' workdir has to be created afterwards; and
`tmt-reboot` does not work in prepare, so ansible reboots). It reinstalls the
per-commit image (`ghcr.io/...:<sha>-standard`, published by CI), so it
always tests the commit under test rather than a floating tag. The shipped
image stays faithful to base-images; `test-images/tmt/` derives a small
image adding what the harness needs on the guest (`rsync`, `audit`,
`cloud-init`) and baking tmt's workdir (`/var/ARTIFACTS`) into `/var`,
because a reinstall replaces `/var` and the guest's `/var` subvolume is left
unmounted:

- `bootc` - the booted system is running the installed image
- `selinux` - SELinux enforcing
- `systemd` - no failed units
- `initramfs` - kernel/initramfs bootable (BLS entry has `initrd`)
- `rpmdb` - rpmdb at the ostree location, readable by rpm
- `dnf` - package management works
- `composefs` - the booted deployment uses composefs (our images use the
  ostree+composefs model, so this checks the deployment carries a composefs
  image)
- `switch-rollback` - upgrade with `bootc switch`, downgrade with
  `bootc rollback`

```bash
tmt run -a plan -n booted
```

This requires a KVM-capable host (GitHub-hosted runners have no `/dev/kvm`);
in CI it runs on [Testing Farm] via Packit (`.packit.yaml`), like bootc.

[tmt]: https://tmt.readthedocs.io/
[Testing Farm]: https://docs.testing-farm.io/

## CI

`.github/workflows/build.yml` builds **both tiers for amd64 and arm64** on
native GitHub-hosted runners (`ubuntu-latest` and `ubuntu-24.04-arm`), runs
`bootc container lint`, the rootfs tests and the disk test, and on pushes to
`main` (and tags) publishes to GHCR:

    ghcr.io/cverna/bootc-base-imagectl-dnf5:minimal        # multi-arch manifest
    ghcr.io/cverna/bootc-base-imagectl-dnf5:standard       # multi-arch manifest
    ghcr.io/cverna/bootc-base-imagectl-dnf5:latest         # = standard
    ghcr.io/cverna/bootc-base-imagectl-dnf5:<sha>-<tier>   # multi-arch manifest
    ghcr.io/cverna/bootc-base-imagectl-dnf5:<sha>-<tier>-<arch>  # per-arch

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

## Manifests

The manifests under `manifests/` are copied from
[fedora/bootc/base-images] (MIT, Fedora CoreOS Authors — see
`manifests/COPYING`); `manifests/UPSTREAM` records the upstream commit.

## License

MIT. See [LICENSE](LICENSE).
