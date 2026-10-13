# The base image is supplied with `podman build --from <image>`; the cases
# run at build time against the image under test. TIER selects the tier
# (minimal or standard) so cases can assert tier-specific expectations.
FROM localhost/image-to-test
ARG TIER=minimal
ENV TIER=$TIER
COPY . /src
RUN /src/run /
