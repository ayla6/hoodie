#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Fedora Repositories, Build Tools, and Versionlocks
###############################################################################
# Stable, rarely-changed setup shared by every build: third-party repos, the
# dev toolchain, and the distro-synced mesa/libva/qt6 versionlocks that keep
# the CachyOS kernel's userland consistent. Deliberately lives BELOW
# 03-third-party-packages.sh and 04-nvidia.sh (they depend on these locks),
# while the frequently-edited packages.json-driven install/remove runs later in
# build/05-packages-json.sh so package changes don't re-trigger the NVIDIA kmod
# compile.
###############################################################################

echo "::group:: Set Up Repositories"

# negativo17 fedora-multimedia for fuller codec coverage. priority=90 outranks
# Fedora's default (99); higher-priority versions auto-win during install.
# nvidia-* is excluded so the legacy 580xx driver (build/04-nvidia.sh) resolves
# from rpmfusion-nonfree instead of negativo's current 610 series, whose
# nvidia-driver-common would file-conflict with the 580xx packages.
dnf5 config-manager addrepo \
    --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo" || true
dnf5 config-manager setopt fedora-multimedia.priority=90
dnf5 config-manager setopt fedora-multimedia.enabled=1
dnf5 config-manager setopt fedora-multimedia.exclude="nvidia-*"

# ublue-os/packages COPR provides the just framework and system helpers.
dnf5 -y copr enable ublue-os/packages
dnf5 -y install \
    ublue-os-just \
    ublue-os-luks \
    ublue-os-udev-rules \
    ublue-os-update-services

# Ship Flathub for first-boot flatpak preinstall (flatpak-nuke-fedora
# removes Fedora's remotes; this provides the real Flathub).
mkdir -p /etc/flatpak/remotes.d/
curl --retry 3 -fsSLo /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo

echo "::endgroup::"

echo "::group:: Add Build Tools"

dnf5 -y group install development-tools

echo "::endgroup::"

echo "::group:: Override mesa/libva from fedora-multimedia + versionlocks"

# Force the mesa/libva/intel-codec stack to negativo17's fuller versions and
# pin them so a future Fedora upgrade doesn't flip-flop.
OVERRIDES=(
    intel-gmmlib
    intel-mediasdk
    intel-vpl-gpu-rt
    libheif
    libva
    libva-intel-media-driver
    mesa-dri-drivers
    mesa-filesystem
    mesa-libEGL
    mesa-libGL
    mesa-libgbm
    mesa-va-drivers
    mesa-vulkan-drivers
)
dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

# Prevent partial qt6 upgrades that can break KWin/SDDM on the KDE flavor.
dnf5 versionlock add "qt6-*"

echo "::endgroup::"

echo "Fedora repositories and versionlocks ready!"
