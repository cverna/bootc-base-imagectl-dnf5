# Compose a bootable container image rootfs with dnf5 (no rpm-ostree).
#
# Stage 1 (builder) installs the tooling and runs bootc-dnf5, which uses
# `dnf5 --installroot` plus the bootc glue. Stage 2 is the final image.
#
# Build with nested-container privileges:
#   just build
# which expands to:
#   podman build --security-opt=label=disable --cap-add=all -t localhost/dnf5-bootc .

ARG REPOS_IMAGE=quay.io/fedora/fedora:rawhide

FROM $REPOS_IMAGE AS builder
# python3 for bootc-dnf5, bubblewrap for chroot-like scriptlet execution,
# policycoreutils for setfiles, bootc for the container linter.
RUN dnf -y install python3 bubblewrap policycoreutils bootc
COPY . /src
RUN /src/bootc-dnf5 build-rootfs /src/manifest.json /target-rootfs

# The rootfs composed above, as a scratch image.
FROM scratch
COPY --from=builder /target-rootfs/ /

ARG IMAGE_VERSION=devel
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL containers.bootc 1
LABEL bootc.diskimage-builder quay.io/centos-bootc/bootc-image-builder
ENV container=oci
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
