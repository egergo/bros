# Allow build scripts to be referenced without being copied into the final image
ARG BASE_IMAGE=quay.io/fedora-ostree-desktops/kinoite:44

FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
FROM ${BASE_IMAGE}

### [IM]MUTABLE /opt
# RUN rm /opt && mkdir /opt

### MODIFICATIONS
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
RUN bootc container lint
