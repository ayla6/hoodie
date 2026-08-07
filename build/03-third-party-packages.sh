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

curl -fsSL https://pkgs.tailscale.com/stable/fedora/noarch/tailscale.repo \
    -o /etc/yum.repos.d/tailscale.repo
dnf5 -y install tailscale

echo "::endgroup::"

echo "::group:: Disable Third-Party Repositories"

# negativo17 and tailscale are done being used; keep them disabled in the
# final image. CachyOS is disabled at the end of 04-nvidia.sh once the kmod
# has been compiled.
for repo in negativo17-fedora-multimedia tailscale; do
    if [[ -f "/etc/yum.repos.d/${repo}.repo" ]]; then
        sed -i 's@enabled=1@enabled=0@g' "/etc/yum.repos.d/${repo}.repo"
    fi
done

echo "::endgroup::"

echo "Third-party package installation complete!"
