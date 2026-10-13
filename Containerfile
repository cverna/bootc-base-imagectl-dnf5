# Compose a bootable container image rootfs with dnf5 (no rpm-ostree).
#
# Stage 1 (builder) installs the tooling and runs bootc-base-imagectl, which
# resolves one of the manifests vendored under manifests/ (the same format as
# https://gitlab.com/fedora/bootc/base-images) and composes the rootfs with
# `dnf5 --installroot` plus the bootc glue. Stage 2 is the final image.
#
# Build with nested-container privileges:
#   just build tier=minimal
# which expands to:
#   podman build --security-opt=label=disable --cap-add=all \
#       --build-arg=MANIFEST=minimal -t localhost/bootc-base-imagectl-dnf5:minimal .

ARG REPOS_IMAGE=quay.io/fedora/fedora:rawhide
# Content tier: standard (default) or minimal.
ARG MANIFEST=standard

FROM $REPOS_IMAGE AS builder
# ARGs declared before FROM are not visible inside the stage.
ARG MANIFEST=standard
# python3 + PyYAML for bootc-base-imagectl, bubblewrap for chroot-like
# scriptlet execution, policycoreutils for setfiles, bootc for the linter.
RUN dnf -y install python3 python3-pyyaml bubblewrap policycoreutils bootc
COPY . /src
RUN /src/bootc-base-imagectl build-rootfs \
        --manifestdir=/src/manifests ${MANIFEST} /target-rootfs

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
