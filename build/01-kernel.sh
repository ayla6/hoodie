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

# Workaround for coreos/rpm-ostree#5578: `rpm-ostree kernel-install add`
# runs dracut before depmod, so a freshly-installed third-party kernel has
# no modules.dep and dracut fails. Symlinking 50-depmod.install to a name
# that sorts before 05-rpmostree.install makes depmod run first.
ln -s 50-depmod.install /usr/lib/kernel/install.d/01-depmod.install

# Same override-replace flow the COPR documents for Silverblue. The stock
# kernel packages are removed and replaced by the CachyOS ones, matched
# -devel provides the headers the NVIDIA akmod needs.
rpm-ostree override remove \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra \
    --install kernel-cachyos \
    --install kernel-cachyos-devel \
    --install kernel-cachyos-devel-matched

KERNEL_VERSION=$(ls -d /usr/lib/modules/[0-9]* | head -1 | xargs basename)
echo "Active kernel: ${KERNEL_VERSION}"

echo "::endgroup::"

echo "::group:: Install Signing Tools"

dnf5 -y install sbsigntools openssl

echo "::endgroup::"

echo "::group:: Set Up MOK Signing Keys"

# akmods signs out-of-tree modules (e.g. NVIDIA) with these files when present.
mkdir -p /etc/pki/akmods/certs
chmod 700 /etc/pki/akmods

MOK_SUBJECT="/CN=hoodie Secure Boot"

if [[ -f /run/secrets/mokkey ]]; then
    echo "Using MOK private key from build secret"
    install -m 600 /run/secrets/mokkey /etc/pki/akmods/private_key.priv
else
    echo "WARNING: No MOK private key secret provided; generating a fresh keypair"
    echo "WARNING: Secure Boot users must re-enroll this image's key after each rebuild"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/pki/akmods/private_key.priv \
        -out /etc/pki/akmods/certs/public_key.der \
        -outform DER -days 36500 -subj "${MOK_SUBJECT}"
    openssl x509 -inform DER \
        -in /etc/pki/akmods/certs/public_key.der \
        -out /etc/pki/akmods/public_key.pem
fi

# Derive the DER + PEM certificates from the private key so the cert shipped
# in the image always matches the key the modules/kernel were signed with.
if [[ ! -f /etc/pki/akmods/certs/public_key.der ]]; then
    openssl req -x509 -new \
        -key /etc/pki/akmods/private_key.priv \
        -out /etc/pki/akmods/certs/public_key.der \
        -outform DER -days 36500 -subj "${MOK_SUBJECT}"
fi
openssl x509 -inform DER \
    -in /etc/pki/akmods/certs/public_key.der \
    -out /etc/pki/akmods/public_key.pem

chmod 600 /etc/pki/akmods/private_key.priv
chmod 644 /etc/pki/akmods/certs/public_key.der
chmod 644 /etc/pki/akmods/public_key.pem

echo "::endgroup::"

echo "::group:: Sign Kernel for Secure Boot"

# The vmlinuz is an EFI PE binary (EFI stub), so sbsign can attach a signature
# that shim/GRUB verify against the enrolled MOK key.
if [[ ! -f "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" ]]; then
    echo "ERROR: no vmlinuz found for ${KERNEL_VERSION}" >&2
    exit 1
fi

sbsign \
    --key /etc/pki/akmods/private_key.priv \
    --cert /etc/pki/akmods/public_key.pem \
    --output "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" \
    "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

sbverify --cert /etc/pki/akmods/public_key.pem "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

echo "::endgroup::"

echo "Kernel swap and signing complete!"
