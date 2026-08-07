#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Homebrew Setup
###############################################################################
# Configures Homebrew for the hoodie image. The brew system files are imported
# from the ghcr.io/ublue-os/brew build stage in the Containerfile.
###############################################################################

echo "::group:: Install Homebrew System Files"

# Copy Homebrew system files from the brew build stage
rsync -rvKl /ctx/oci/brew/ /

echo "::endgroup::"

echo "::group:: Configure Homebrew Services"

# Set up Homebrew systemd services
systemctl preset brew-setup.service
systemctl preset brew-update.timer
systemctl preset brew-upgrade.timer

echo "::endgroup::"

echo "Homebrew configuration complete!"
