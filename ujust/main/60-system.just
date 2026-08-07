# vim: set ft=make :

# Enable the bees deduplication timer for every btrfs filesystem
[group("System")]
enable-beesd:
    #!/usr/bin/bash
    # Set up bees (btrfs extent dedupe) on each unconfigured btrfs filesystem
    sudo mkdir -p /etc/bees
    while read -r fsid; do
        [[ -n "$fsid" ]] || continue
        conf="/etc/bees/${fsid}.conf"
        if [[ -f "$conf" ]]; then
            echo "$fsid already configured."
            continue
        fi
        # Hash table size ~512MB per TB of filesystem, clamped
        size_bytes=$(sudo lsblk --fs --noheadings --bytes -o SIZE --filter "FSTYPE == \"btrfs\" AND UUID == \"$fsid\"")
        size_tb=$(( size_bytes / 1000**4 ))
        (( size_tb < 1 )) && size_tb=1
        (( size_tb > 4 )) && size_tb=4
        db_size=$(( size_tb * 512 * 1024**2 ))
        sudo cp /usr/etc/bees/beesd.conf.sample "$conf"
        sudo sed -i "s/^UUID=.*/UUID=${fsid}/" "$conf"
        sudo sed -i "s/^# DB_SIZE=.*/DB_SIZE=${db_size}/" "$conf"
        echo "Configured bees for $fsid (DB_SIZE=${db_size})."
    done < <(sudo lsblk --fs --list --noheadings -o UUID --filter 'FSTYPE == "btrfs"' | sort -u)

    sudo systemctl daemon-reload
    for fsid in $(sudo lsblk --fs --list --noheadings -o UUID --filter 'FSTYPE == "btrfs"' | sort -u); do
        [[ -f "/etc/bees/${fsid}.conf" ]] && sudo systemctl enable --now "beesd@${fsid}.timer"
    done
    echo "beesd timers enabled."

# Enroll the hoodie Secure Boot MOK key (needed once to boot the
# self-signed CachyOS kernel and load the signed NVIDIA module).
# Enter the password "hoodie" if prompted.
[group("System")]
enroll-secure-boot-key:
    #!/usr/bin/bash
    if [[ -f /etc/pki/akmods/certs/public_key.der ]]; then
        sudo mokutil --import /etc/pki/akmods/certs/public_key.der
        echo "MOK key queued for enrollment."
        echo "Reboot, then complete enrollment in the blue MokManager screen."
    else
        echo "No hoodie MOK certificate found on this image."
    fi

# Rebase to the other hoodie variant
[group("System")]
rebase-helper:
    #!/usr/bin/bash
    CURRENT_VARIANT=$(grep '^VARIANT_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    case "$CURRENT_VARIANT" in
        hoodie)   IMAGE="ghcr.io/ayla6/hoodie-kde:stable" ;;
        hoodie-kde) IMAGE="ghcr.io/ayla6/hoodie:stable" ;;
        *)        echo "Not running a hoodie variant."; exit 1 ;;
    esac
    echo "Rebasing to $IMAGE..."
    sudo rpm-ostree rebase ostree-image-signed:docker://$IMAGE
    echo "Rebase complete! Reboot to apply."
