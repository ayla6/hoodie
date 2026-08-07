###############################################################################
# BUILD ARGUMENTS
###############################################################################
# Static values enable Renovate to detect and update each base image digest.
ARG BASE_IMAGE_GNOME="ghcr.io/ublue-os/silverblue-main:44@sha256:da9d42dddda2a2336b27cbda88dc6370a59f3530b8b678d04355589cb93d5090"
ARG BASE_IMAGE_KDE="ghcr.io/ublue-os/kinoite-main:44@sha256:73ca59ba8b2209c13975610a7a184a6fd2c757ac1e94780934d7215bf0928f72"
ARG BASE_IMAGE="${BASE_IMAGE_GNOME}"

# Brew image provides Homebrew system files for import.
ARG BREW_IMAGE="ghcr.io/ublue-os/brew:latest"
ARG BREW_IMAGE_SHA="sha256:8855464e5c150974c5edf4343ffef50ca37b1c4d96a648dce28927033010a372"

###############################################################################
# IMPORT STAGES
###############################################################################
FROM ${BREW_IMAGE}@${BREW_IMAGE_SHA} AS brew

FROM scratch AS ctx
COPY /build /build
COPY /files /files
COPY /flatpaks /flatpaks
COPY /ujust /ujust
COPY /packages.json /packages.json
COPY /services.json /services.json

# Import Homebrew files (rsynced into the image in build/07-homebrew.sh)
COPY --from=brew /system_files /oci/brew

###############################################################################
# MAIN IMAGE
###############################################################################
FROM ${BASE_IMAGE} AS base

# Build arguments for image metadata and variant selection
ARG IMAGE_NAME="hoodie"
ARG IMAGE_VENDOR="ayla6"
ARG IMAGE_FLAVOR="gnome"
ARG SHA_HEAD_SHORT=""
ARG UBLUE_IMAGE_TAG="stable"

# Labels for image metadata
LABEL org.opencontainers.image.name="${IMAGE_NAME}"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL org.opencontainers.image.flavor="${IMAGE_FLAVOR}"
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"

###############################################################################
# BUILD PROCESS
###############################################################################
# 01-kernel swaps in the CachyOS kernel and signs it for Secure Boot.
# The optional `mokkey` secret is the stable MOK private key; without it a
# fresh keypair is generated for the build.
RUN --mount=type=secret,id=mokkey,required=false \
    --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/01-kernel.sh

# 02-fedora-packages installs/removes packages from Fedora repositories.
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/02-fedora-packages.sh

# 03-third-party-packages installs from COPRs and other third-party repos.
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/03-third-party-packages.sh

# 04-nvidia installs the legacy 580xx driver and signs the built kmod.
# Must follow 01-kernel (needs CachyOS kernel headers) and 03 (repos).
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/04-nvidia.sh

# 07-homebrew imports the brew system files. Kept below the package/kernel
# layers (stable) and ABOVE 05-copy-files so our custom overlays are staged
# last and win any filename clash with brew's system files.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build/07-homebrew.sh

# 05-copy-files stages variant overlays, ujust recipes, and flatpak
# preinstalls. It lives near the top of the layer stack so editing files/,
# ujust/, or flatpaks/ only rebuilds the outermost layers -> smaller diffs.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/05-copy-files.sh

# 06-systemd enables units that may be shipped by step 05; must follow it.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/06-systemd.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    IMAGE_NAME="${IMAGE_NAME}" \
    IMAGE_VENDOR="${IMAGE_VENDOR}" \
    SHA_HEAD_SHORT="${SHA_HEAD_SHORT}" \
    UBLUE_IMAGE_TAG="${UBLUE_IMAGE_TAG}" \
    /ctx/build/08-branding.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    IMAGE_FLAVOR="${IMAGE_FLAVOR}" \
    /ctx/build/09-cleanup.sh

###############################################################################
# FINALIZE
###############################################################################
RUN bootc container lint
