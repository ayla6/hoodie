#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Fedora Package Installation
###############################################################################
# Installs and removes packages from Fedora repositories only, driven by
# packages.json. Third-party repositories are handled in
# 03-third-party-packages.sh and 04-nvidia.sh.
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

echo "::group:: Validate packages.json"

if ! jq empty /ctx/packages.json 2>/dev/null; then
    echo "ERROR: packages.json contains syntax errors and cannot be parsed" >&2
    exit 1
fi

echo "::endgroup::"

echo "::group:: Build Package Lists"

INCLUDED_PACKAGES=()
EXCLUDED_PACKAGES=()

# Split IMAGE_FLAVOR into array of variant names. Always includes "main" as
# the shared base applied to every image.
IFS='-' read -ra FLAVOR_PARTS <<<"${IMAGE_FLAVOR}"

for variant in main "${FLAVOR_PARTS[@]}"; do
    if jq -e ".variants.${variant}" /ctx/packages.json >/dev/null 2>&1; then
        echo "Processing packages for variant: ${variant}"

        if jq -e ".variants.${variant}.include" /ctx/packages.json >/dev/null 2>&1; then
            readarray -t VARIANT_PACKAGES < <(jq -r ".variants.${variant}.include | sort | unique[]" /ctx/packages.json)
            INCLUDED_PACKAGES+=("${VARIANT_PACKAGES[@]}")
        fi

        if jq -e ".variants.${variant}.exclude" /ctx/packages.json >/dev/null 2>&1; then
            readarray -t VARIANT_EXCLUDED < <(jq -r ".variants.${variant}.exclude | sort | unique[]" /ctx/packages.json)
            EXCLUDED_PACKAGES+=("${VARIANT_EXCLUDED[@]}")
        fi
    fi
done

echo "::endgroup::"

echo "::group:: Install Fedora Packages"

if [[ ${#INCLUDED_PACKAGES[@]} -gt 0 ]]; then
    dnf5 -y install \
        "${INCLUDED_PACKAGES[@]}"
else
    echo "No packages to install."
fi

echo "::endgroup::"

echo "::group:: Remove Excluded Packages"

if [[ ${#EXCLUDED_PACKAGES[@]} -gt 0 ]]; then
    INSTALLED_EXCLUDED=()
    for pkg in "${EXCLUDED_PACKAGES[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            INSTALLED_EXCLUDED+=("$pkg")
        fi
    done
    EXCLUDED_PACKAGES=("${INSTALLED_EXCLUDED[@]}")
fi

if [[ ${#EXCLUDED_PACKAGES[@]} -gt 0 ]]; then
    dnf5 -y remove \
        "${EXCLUDED_PACKAGES[@]}"
else
    echo "No packages to remove."
fi

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

echo "Fedora package installation complete!"
