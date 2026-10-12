# The base image is supplied with `podman build --from <image>`; the cases
# run at build time against the image under test.
FROM localhost/image-to-test
COPY . /src
RUN /src/run /
