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

echo "::group:: Enable rpmfusion-nonfree"

# ublue main bases don't ship rpmfusion at all; install the release package so
# the 580xx driver and kmod source can resolve. rpmfusion-nonfree-release no
# longer requires free (rpmfusion commit "Drop dependency on free from
# nonfree"), so the nonfree repo alone is enough for the NVIDIA packages.
dnf5 -y install \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

echo "::endgroup::"

echo "::group:: Install NVIDIA 580xx Driver"

# Pick the CachyOS kernel explicitly: the base image can still carry stock
# module dirs (e.g. 7.1.6-201), and plain `ls | head -1` is sort-order
# dependent. We only ever sign/build against the CachyOS kernel from 01.
KERNEL_VERSION=$(ls -d /usr/lib/modules/*cachyos* | head -1 | xargs basename)
echo "Building NVIDIA kmod for kernel: ${KERNEL_VERSION}"

# akmods must be installed with its scriptlets running so its %pre creates the
# dedicated build user (and %post enables its units) -- the explicit akmods run
# below drops privileges to that user via runuser.
dnf5 -y install akmods

# The kmod build (akmodsbuild -> rpmbuild) drops to the `akmods` user, which
# must be able to read the MOK private key seeded in 01-kernel.sh. Without this
# the signing guard in /etc/rpm/macros.kmodtool still passes but brp-kmodsign
# fails, leaving the kmod unsigned.
chgrp -R akmods /etc/pki/akmods
chmod 750 /etc/pki/akmods /etc/pki/akmods/private /etc/pki/akmods/certs
chmod 640 /etc/pki/akmods/private/private_key.priv
chmod 644 /etc/pki/akmods/certs/public_key.der /etc/pki/akmods/public_key.pem

# akmod-nvidia-580xx pulls in the kmod source; the xorg driver is the closed
# GL/Vulkan/DDX stack for the legacy branch.
#
# Scriptlets are suppressed on this transaction: rpmfusion's akmod %post runs
# /usr/sbin/akmods-ostree-post, which (in an ostree-detected environment)
# tries to build the kmod for every kernel in /lib/modules as root. akmodsbuild
# refuses to run as root, so that %post aborts the whole dnf transaction. Its
# %posttrans also spawns a detached background build. We compile explicitly
# below via `akmods --force --kernels`, which drops privileges to the akmods
# user the way the package intends.
dnf5 -y install --setopt=tsflags=noscripts \
    akmod-nvidia-580xx \
    xorg-x11-drv-nvidia-580xx \
    xorg-x11-drv-nvidia-580xx-power

echo "::endgroup::"

echo "::group:: Compile and Sign NVIDIA kmod"

# akmods builds the module against the installed CachyOS headers and signs it
# with /etc/pki/akmods (private_key.priv + certs/public_key.der from 01).
akmods --force --kernels "${KERNEL_VERSION}"

# kmodtool strips "-kmod" from the akmod name, so the modules land in
# extra/nvidia-580xx/ (not extra/nvidia/) even though the binary is nvidia.ko.
# The CachyOS kernel enables CONFIG_MODULE_COMPRESS_XZ, so the built modules
# are shipped (and installed) as nvidia.ko.xz.
NVIDIA_MODULE="/usr/lib/modules/${KERNEL_VERSION}/extra/nvidia-580xx/nvidia.ko.xz"
if [[ ! -f "${NVIDIA_MODULE}" ]]; then
    echo "ERROR: akmods did not produce ${NVIDIA_MODULE}" >&2
    ls -la "/usr/lib/modules/${KERNEL_VERSION}/extra/nvidia-580xx/" || true
    exit 1
fi

# Verify the built module carries our MOK signature. A build that produces an
# unsigned kmod would silently fail to load under Secure Boot, so this is a
# hard failure rather than a warning.
SIGNER=$(modinfo "${NVIDIA_MODULE}" | awk -F': ' '/signer/{print $2}')
echo "NVIDIA module signer: ${SIGNER}"
if [[ -z "${SIGNER}" ]]; then
    echo "ERROR: ${NVIDIA_MODULE} is not signed (empty signer)" >&2
    echo "ERROR: check /etc/pki/akmods/private/private_key.priv + kmodtool signing macros" >&2
    exit 1
fi
if [[ "${SIGNER}" != "hoodie Secure Boot" ]]; then
    echo "ERROR: ${NVIDIA_MODULE} signed by unexpected key '${SIGNER}'" >&2
    exit 1
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
