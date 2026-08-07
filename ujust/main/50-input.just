# vim: set ft=make :

# Enable the input-remapper service (configure the 8BitDo controller in its GUI)
[group("Hardware")]
setup-input-remapper:
    #!/usr/bin/bash
    sudo systemctl enable --now input-remapper.service
    echo "input-remapper enabled. Configure your device in the input-remapper app."

# Force full RGB range on Intel HDMI outputs (X11) to fix washed-out color
[group("Hardware")]
rgb-full:
    #!/usr/bin/bash
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        echo "On Wayland, set the full color range in GNOME:"
        echo "Settings > Displays > select the monitor > Color > choose the full-range profile."
        exit 0
    fi
    for output in $(xrandr --listmonitors | grep -oE 'HDMI[^ ]+' | sort -u); do
        xrandr --output "$output" --set "Broadcast RGB" "Full" \
            && echo "Set full RGB on $output"
    done

# Print the current RGB output range on each Intel output
[group("Hardware")]
rgb-debug:
    #!/usr/bin/bash
    for output in $(xrandr --listmonitors | grep -oE 'HDMI[^ ]+' | sort -u); do
        xrandr --verbose | awk -v out="$output" '
            $1 == out { printing=1 }
            printing && /Broadcast RGB/ { print out ": " $3; printing=0 }
        '
    done

# Show GPU vendor and connected display outputs (RGB fix targets Intel iGPU)
[group("Hardware")]
gpu-topology:
    #!/usr/bin/bash
    for card in /sys/class/drm/card*; do
        [[ -e "$card/device/vendor" ]] || continue
        vendor=$(cat "$card/device/vendor")
        name=$(lspci -d "$vendor" 2>/dev/null | head -1 | sed 's/.*: //')
        echo "=== $(basename "$card"): $name ==="
        for conn in "$card"/card*-*/; do
            [[ -e "$conn/status" ]] || continue
            printf "  %-14s %s\n" "$(basename "$conn")" "$(cat "$conn/status")"
        done
    done
