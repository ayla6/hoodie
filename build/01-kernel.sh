#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# CachyOS Kernel + Secure Boot Signing
###############################################################################
# Swaps the stock Fedora kernel for kernel-cachyos (BORE scheduler + 1000Hz)
# from the bieszczaders COPR, then signs the kernel image so Secure Boot
# can stay enabled. The matching akmod signing key is also seeded for the
# NVIDIA kmod built later in build/04-nvidia.sh.
#
# The MOK private key is read from the optional `mokkey` build secret
# (/run/secrets/mokkey). When absent a fresh keypair is generated so the
# build can proceed, at the cost of needing to re-enroll after each rebuild.
# Keep a stable key for production images (see README).
###############################################################################

echo "::group:: Enable CachyOS COPR"

dnf5 -y copr enable bieszczaders/kernel-cachyos

echo "::endgroup::"

echo "::group:: Swap Kernel to CachyOS"

# Swap the stock Fedora kernel for CachyOS the same way ublue's own base-image
# build does (ublue-os/main build_files/install.sh): plain `rpm --erase
# --nodeps` + `dnf5 install`, with kernel-install's rpmostree/dracut hooks
# shimmed out. This bypasses rpm-ostree's FilesystemScriptPrep machinery,
# which intermittently fails in CI with "Undoing prep filesystem for scripts:
# Invalid argument (os error 22)".
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    rpm --erase "$pkg" --nodeps
done

# Shim kernel-install's rpmostree + dracut hooks so the kernel %post during
# the dnf5 install can't trigger dracut before depmod (coreos/rpm-ostree#5578)
# or rpm-ostree at all. The initramfs is generated explicitly below.
KERNEL_INSTALL_D="/usr/lib/kernel/install.d"
mv "${KERNEL_INSTALL_D}/05-rpmostree.install" "${KERNEL_INSTALL_D}/05-rpmostree.install.bak"
mv "${KERNEL_INSTALL_D}/50-dracut.install" "${KERNEL_INSTALL_D}/50-dracut.install.bak"
printf '%s\n' '#!/bin/sh' 'exit 0' > "${KERNEL_INSTALL_D}/05-rpmostree.install"
printf '%s\n' '#!/bin/sh' 'exit 0' > "${KERNEL_INSTALL_D}/50-dracut.install"
chmod +x "${KERNEL_INSTALL_D}/05-rpmostree.install" "${KERNEL_INSTALL_D}/50-dracut.install"

# The -devel-matched package provides the exact-version headers the NVIDIA
# akmod build needs later in build/04-nvidia.sh.
dnf5 -y install \
    kernel-cachyos \
    kernel-cachyos-devel \
    kernel-cachyos-devel-matched

# Restore the real kernel-install hooks for the final image.
mv -f "${KERNEL_INSTALL_D}/05-rpmostree.install.bak" "${KERNEL_INSTALL_D}/05-rpmostree.install"
mv -f "${KERNEL_INSTALL_D}/50-dracut.install.bak" "${KERNEL_INSTALL_D}/50-dracut.install"

# The base image's stock kernel leaves stale /lib/modules dirs behind: rpm
# --erase removes the kernel RPMs but not build-generated files like the
# initramfs.img, so the whole dir survives. Keep only the CachyOS kernel so
# akmods/build tooling and the final image never see a phantom stock kernel.
for d in /usr/lib/modules/*/; do
    case "${d}" in
        *cachyos*) ;;
        *) rm -rf "${d}" ;;
    esac
done

# Pin the CachyOS kernel so later dnf transactions can't replace it.
dnf5 versionlock add \
    kernel-cachyos \
    kernel-cachyos-core \
    kernel-cachyos-modules \
    kernel-cachyos-modules-core \
    kernel-cachyos-modules-extra \
    kernel-cachyos-devel \
    kernel-cachyos-devel-matched

# Pick the CachyOS kernel explicitly; stock module dirs may linger in the
# base image and plain `ls | head -1` is sort-order dependent.
KERNEL_VERSION=$(ls -d /usr/lib/modules/*cachyos* | head -1 | xargs basename)
echo "Active kernel: ${KERNEL_VERSION}"

# The kernel-install hooks were bypassed, so build the initramfs manually in
# the right order: depmod first, then dracut with ostree support (matching
# ublue's build_files/initramfs.sh).
depmod "${KERNEL_VERSION}"
DRACUT_NO_XATTR=1 /usr/bin/dracut \
    --no-hostonly \
    --kver "${KERNEL_VERSION}" \
    --reproducible \
    -v \
    --add ostree \
    -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

echo "::endgroup::"

echo "::group:: Install Signing Tools"

dnf5 -y install sbsigntools openssl

echo "::endgroup::"

echo "::group:: Set Up MOK Signing Keys"

# akmods signs out-of-tree modules (e.g. NVIDIA) with these files when present.
# kmodtool's signing macros (/etc/rpm/macros.kmodtool) hard-code the private
# key to /etc/pki/akmods/private/private_key.priv and the public cert to
# /etc/pki/akmods/certs/public_key.der -- a build only signs the kmod if both
# exist, so the paths must match exactly (note the `private/` subdir).
mkdir -p /etc/pki/akmods/certs /etc/pki/akmods/private
chmod 700 /etc/pki/akmods

MOK_SUBJECT="/CN=hoodie Secure Boot"

MOK_PRIVKEY=/etc/pki/akmods/private/private_key.priv
MOK_CERT_DER=/etc/pki/akmods/certs/public_key.der
MOK_CERT_PEM=/etc/pki/akmods/public_key.pem

if [[ -f /run/secrets/mokkey ]]; then
    echo "Using MOK private key from build secret"
    install -m 600 /run/secrets/mokkey "${MOK_PRIVKEY}"
else
    echo "WARNING: No MOK private key secret provided; generating a fresh keypair"
    echo "WARNING: Secure Boot users must re-enroll this image's key after each rebuild"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${MOK_PRIVKEY}" \
        -out "${MOK_CERT_DER}" \
        -outform DER -days 36500 -subj "${MOK_SUBJECT}"
fi

# Derive the DER + PEM certificates from the private key so the cert shipped
# in the image always matches the key the modules/kernel were signed with.
if [[ ! -f "${MOK_CERT_DER}" ]]; then
    openssl req -x509 -new \
        -key "${MOK_PRIVKEY}" \
        -out "${MOK_CERT_DER}" \
        -outform DER -days 36500 -subj "${MOK_SUBJECT}"
fi
openssl x509 -inform DER \
    -in "${MOK_CERT_DER}" \
    -out "${MOK_CERT_PEM}"

chmod 600 "${MOK_PRIVKEY}"
chmod 644 "${MOK_CERT_DER}"
chmod 644 "${MOK_CERT_PEM}"

echo "::endgroup::"

echo "::group:: Sign Kernel for Secure Boot"

# The vmlinuz is an EFI PE binary (EFI stub), so sbsign can attach a signature
# that shim/GRUB verify against the enrolled MOK key.
if [[ ! -f "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" ]]; then
    echo "ERROR: no vmlinuz found for ${KERNEL_VERSION}" >&2
    exit 1
fi

sbsign \
    --key "${MOK_PRIVKEY}" \
    --cert "${MOK_CERT_PEM}" \
    --output "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" \
    "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

sbverify --cert "${MOK_CERT_PEM}" "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

echo "::endgroup::"

echo "Kernel swap and signing complete!"
