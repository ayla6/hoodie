#!/usr/bin/env bash

# shellcheck disable=SC1091,SC2154
set -eoux pipefail

echo "::group:: Applying OS Release Branding"

###############################################################################
# OS Release Branding
###############################################################################
# Complete branding changes to make the system identify as "hoodie" while
# maintaining full Fedora compatibility.
###############################################################################

IMAGE_PRETTY_NAME="hoodie"
IMAGE_LIKE="fedora"
IMAGE_VENDOR="${IMAGE_VENDOR:-aylac}"
IMAGE_NAME="${IMAGE_NAME:-hoodie}"
IMAGE_FLAVOR="${IMAGE_FLAVOR:-gnome}"
IMAGE_TAG="${UBLUE_IMAGE_TAG:-stable}"
FEDORA_VERSION="44"
VERSION="${VERSION:-44}"
HOME_URL="https://github.com/${IMAGE_VENDOR}/hoodie"
DOCUMENTATION_URL="https://github.com/${IMAGE_VENDOR}/hoodie/blob/main/README.md"
SUPPORT_URL="https://github.com/${IMAGE_VENDOR}/hoodie/issues/"
BUG_SUPPORT_URL="https://github.com/${IMAGE_VENDOR}/hoodie/issues/"

case "${IMAGE_FLAVOR}" in
    gnome) BASE_IMAGE_NAME="silverblue" ;;
    kde) BASE_IMAGE_NAME="kinoite" ;;
    *) BASE_IMAGE_NAME="${IMAGE_FLAVOR}" ;;
esac

# Create image-info.json
mkdir -p /usr/share/ublue-os
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

cat >$IMAGE_INFO <<EOF
{
  "image-name": "$IMAGE_NAME",
  "image-flavor": "$IMAGE_FLAVOR",
  "image-vendor": "$IMAGE_VENDOR",
  "image-ref": "$IMAGE_REF",
  "image-tag": "$IMAGE_TAG",
  "base-image-name": "$BASE_IMAGE_NAME",
  "fedora-version": "$FEDORA_VERSION"
}
EOF

# Modify OS Release File
sed -i "s|^VARIANT_ID=.*|VARIANT_ID=$IMAGE_NAME|" /usr/lib/os-release
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${IMAGE_PRETTY_NAME} (Version: ${VERSION})\"|" /usr/lib/os-release
sed -i "s|^NAME=.*|NAME=\"$IMAGE_PRETTY_NAME\"|" /usr/lib/os-release
sed -i "s|^HOME_URL=.*|HOME_URL=\"$HOME_URL\"|" /usr/lib/os-release
sed -i "s|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL=\"$DOCUMENTATION_URL\"|" /usr/lib/os-release
sed -i "s|^SUPPORT_URL=.*|SUPPORT_URL=\"$SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"$BUG_SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^CPE_NAME=\"cpe:/o:fedoraproject:fedora|CPE_NAME=\"cpe:/o:universal-blue:${IMAGE_PRETTY_NAME,}|" /usr/lib/os-release
sed -i "s|^DEFAULT_HOSTNAME=.*|DEFAULT_HOSTNAME=\"${IMAGE_PRETTY_NAME,}\"|" /usr/lib/os-release
sed -i "/^ID=fedora/a ID_LIKE=\"${IMAGE_LIKE}\"" /usr/lib/os-release
sed -i "/^REDHAT_BUGZILLA_PRODUCT=/d; /^REDHAT_BUGZILLA_PRODUCT_VERSION=/d; /^REDHAT_SUPPORT_PRODUCT=/d; /^REDHAT_SUPPORT_PRODUCT_VERSION=/d" /usr/lib/os-release

# Add BUILD_ID if available
if [[ -n ${SHA_HEAD_SHORT:-} ]]; then
    echo "BUILD_ID=\"$SHA_HEAD_SHORT\"" >>/usr/lib/os-release
fi

# Add IMAGE_ID and IMAGE_VERSION (systemd 249+)
echo "IMAGE_ID=\"$IMAGE_NAME\"" >>/usr/lib/os-release
echo "IMAGE_VERSION=\"$VERSION\"" >>/usr/lib/os-release

# Fix issues caused by ID no longer being fedora
sed -i 's|^EFIDIR=.*|EFIDIR="fedora"|' /usr/sbin/grub2-switch-to-blscfg

echo "::endgroup::"

echo "OS Release branding applied successfully!"
