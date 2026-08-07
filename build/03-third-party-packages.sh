#!/usr/bin/env bash

set -eoux pipefail

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

###############################################################################
# Third-Party Package Installation
###############################################################################
# Installs packages from third-party repositories (non-COPR), then disables
# repositories that are no longer needed for the rest of the build.
###############################################################################

echo "::group:: Install Tailscale"

# Same repo-add pattern Bazzite uses: download the repo metadata via dnf's
# config-manager rather than curl, then install the client. The distro
# component resolves to $basearch, so there is no /noarch/ in the URL.
dnf5 config-manager addrepo --overwrite \
    --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 -y install tailscale

echo "::endgroup::"

echo "::group:: Install umu-launcher from Terra"

# umu-launcher isn't in Fedora; Bazzite pulls it from Terra (Fyra Labs).
# Only the base terra repo is needed (no extras/mesa/nvidia variants).
dnf5 -y install --nogpgcheck \
    --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
    terra-release
dnf5 -y --enable-repo=terra install umu-launcher

echo "::endgroup::"

echo "::group:: Install Steam from Terra"

# Steam isn't in Fedora either; Terra ships it with its 32-bit runtime deps.
# 02-fedora-repos.sh versionlocked mesa* to the fedora-multimedia (x86_64
# only) EVR, which would make Steam's mesa-*(x86-32) deps unresolvable. Clear
# those locks for this transaction only; the versionlocks are gone from the
# final image anyway (10-cleanup.sh).
dnf5 versionlock delete 'mesa-*'
dnf5 -y --enable-repo=terra --setopt=install_weak_deps=False install steam
dnf5 versionlock add 'mesa-*'

echo "::endgroup::"

echo "::group:: Disable Third-Party Repositories"

# negativo17, tailscale, and terra are done being used; keep them disabled in
# the final image. CachyOS is disabled at the end of 04-nvidia.sh once the
# kmod has been compiled.
for repo in negativo17-fedora-multimedia tailscale terra terra-extras terra-mesa terra-multimedia terra-nvidia; do
    if [[ -f "/etc/yum.repos.d/${repo}.repo" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "/etc/yum.repos.d/${repo}.repo"
    fi
done

echo "::endgroup::"

echo "Third-party package installation complete!"
