#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Fedora Package Installation (packages.json-driven)
###############################################################################
# Installs and removes packages from Fedora repositories only, driven by
# packages.json. Deliberately lives ABOVE 04-nvidia.sh: packages.json is the
# most-edited file, and the expensive akmod/NVIDIA kmod compile must not run
# again just because a package was added. Third-party repositories are handled
# in 03-third-party-packages.sh and 04-nvidia.sh; the versionlocks pinned in
# 02-fedora-repos.sh ensure the CachyOS kernel's userland stays consistent.
###############################################################################

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

echo "Fedora package installation complete!"
