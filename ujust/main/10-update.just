# vim: set ft=make :

alias upgrade := update

# Update system, flatpaks, and containers all at once via uupd
update:
    #!/usr/bin/bash
    echo "Updating system, flatpaks, and containers (uupd)..."
    sudo uupd
    echo "Update complete."

alias changelog := changelogs

# Show the changelog
changelogs:
    #!/usr/bin/bash
    rpm-ostree db diff --changelogs 2>/dev/null || \
        echo "Changelog not available."

# Update device firmware
[no-exit-message]
update-firmware:
    fwupdmgr refresh --force
    fwupdmgr get-updates
    fwupdmgr update

alias auto-update := toggle-updates

# Turn automatic updates (uupd.timer) on or off
toggle-updates:
    #!/usr/bin/bash
    if systemctl -q is-enabled uupd.timer 2>/dev/null; then
        CURRENT_STATE="Enabled"
    else
        CURRENT_STATE="Disabled"
    fi
    echo "Automatic updates are currently: ${CURRENT_STATE}"
    echo "Enable or Disable automatic updates?"
    OPTION=$(gum choose Enable Disable)
    if [ "${OPTION}" == "Enable" ]; then
        sudo systemctl enable --now uupd.timer
        echo "Automatic updates enabled."
    elif [ "${OPTION}" == "Disable" ]; then
        sudo systemctl disable --now uupd.timer
        echo "Automatic updates disabled."
    fi
