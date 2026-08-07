#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Final Cleanup and Configuration
###############################################################################
# Performs final cleanup tasks and system tweaks.
###############################################################################

echo "::group:: Hide Desktop Files"

# Hidden removes mime associations for CLI tools without GUIs.
for file in htop nvtop; do
    if [[ -f "/usr/share/applications/${file}.desktop" ]]; then
        desktop-file-edit --set-key=Hidden --set-value=true /usr/share/applications/${file}.desktop
    fi
done

echo "::endgroup::"

echo "::group:: Remove dnf5 versionlocks"

# Mesa/libva/qt6 were pinned during the build (see 02-fedora-repos.sh) so
# distro-sync could upgrade them without flip-flopping. Clear the locks for the
# final image so users get updates normally (matches ublue-main post-install).
dnf5 versionlock clear

echo "::endgroup::"

echo "::group:: Fix bootc lint issues"

# Fix /var/run symlink if it was broken by package installation (e.g., Steam)
if [[ -d /var/run ]] && [[ ! -L /var/run ]]; then
    echo "Fixing /var/run symlink..."
    rm -rf /var/run
    ln -sf /run /var/run
fi

# Convenience /data -> /var/data symlink. Baked in even though /var/data only
# exists at runtime (a dangling link is harmless and resolves once the dir is
# created); /var lives on the writable partition so the link target survives.
if [[ ! -e /data ]]; then
    echo "Creating /data -> /var/data symlink"
    ln -s /var/data /data
fi

# Clean up /var and /run content created during build.
echo "Cleaning up temporary build artifacts..."
rm -rf /var/lib/dnf
rm -rf /run/faillock
rm -rf /run/sepermit
rm -rf /tmp/*

echo "::endgroup::"

echo "::group:: Disable Remaining Third-Party Repositories"

# Defensive sweep: any repo we enabled for the build should be off in the
# final image (ublue-os/packages stays enabled, matching the base).
for repo in /etc/yum.repos.d/_copr_bieszczaders*.repo; do
    [[ -f "${repo}" ]] && sed -i 's@enabled=1@enabled=0@g' "${repo}"
done

echo "::endgroup::"

echo "Final cleanup and configuration complete!"
