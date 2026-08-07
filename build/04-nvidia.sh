#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# NVIDIA 580xx (Maxwell/Pascal legacy) Driver
###############################################################################
# Installs the closed legacy driver for the MX130 from rpmfusion-nonfree and
# compiles the matching kmod against the CachyOS kernel headers installed in
# 01-kernel.sh. akmods signs the built modules with the MOK key seeded by
# 01-kernel.sh so Secure Boot stays functional.
###############################################################################

echo "::group:: Ensure rpmfusion-nonfree"

# ublue bases ship rpmfusion; make sure the nonfree repo is enabled.
dnf5 config-manager setopt rpmfusion-nonfree.enabled=1

echo "::endgroup::"

echo "::group:: Install NVIDIA 580xx Driver"

KERNEL_VERSION=$(ls -d /usr/lib/modules/[0-9]* | head -1 | xargs basename)
echo "Building NVIDIA kmod for kernel: ${KERNEL_VERSION}"

# akmod-nvidia-580xx pulls in akmods + the kmod source; the xorg driver is
# the closed GL/Vulkan/DDX stack for the legacy branch.
dnf5 -y install \
    akmod-nvidia-580xx \
    xorg-x11-drv-nvidia-580xx \
    xorg-x11-drv-nvidia-580xx-power

echo "::endgroup::"

echo "::group:: Compile and Sign NVIDIA kmod"

# akmods builds the module against the installed CachyOS headers and signs it
# with /etc/pki/akmods (private_key.priv + certs/public_key.der from 01).
akmods --force --kernels "${KERNEL_VERSION}"

NVIDIA_MODULE="/usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/nvidia.ko"
if [[ ! -f "${NVIDIA_MODULE}" ]]; then
    echo "ERROR: akmods did not produce ${NVIDIA_MODULE}" >&2
    ls -la "/usr/lib/modules/${KERNEL_VERSION}/extra/nvidia/" || true
    exit 1
fi

# Verify the built module carries our MOK signature.
SIGNER=$(modinfo "${NVIDIA_MODULE}" | awk -F': ' '/signer/{print $2}')
echo "NVIDIA module signer: ${SIGNER}"
if [[ -n "${SIGNER}" ]] && [[ "${SIGNER}" != "hoodie Secure Boot" ]]; then
    echo "WARNING: NVIDIA module signed by unexpected key '${SIGNER}'" >&2
fi

# Refresh module dependency metadata so the freshly built modules resolve.
depmod "${KERNEL_VERSION}"

echo "::endgroup::"

echo "::group:: Remove Kernel Headers and Disable CachyOS Repo"

# Kernel headers are only needed for building; slim the image afterwards.
rpm -e kernel-cachyos-devel kernel-cachyos-devel-matched --nodeps || true

# CachyOS is done being used; keep the repo disabled in the final image.
dnf5 -y copr disable bieszczaders/kernel-cachyos || true

echo "::endgroup::"

echo "NVIDIA driver installation complete!"
