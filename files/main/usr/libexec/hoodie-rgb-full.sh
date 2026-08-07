#!/usr/bin/env bash
# Force full RGB output range (0-255) on connected HDMI displays instead of
# the limited 16-235 TV range that Intel iGPUs pick when a monitor reports
# 1080p, which washes out colors. Runs before the display manager (while this
# process still owns the DRM master) via the gdm/sddm ExecStartPre drop-ins;
# xrandr can't reach the hardware on Wayland, so we talk to DRM directly via
# libdrm's proptest. Connector/property IDs are discovered, not hardcoded.

set -euo pipefail

PROPTEST="/usr/bin/proptest"
VALUE_FULL=1 # enum: Automatic=0 Full=1 Limited 16:235=2

[[ -x "${PROPTEST}" ]] || exit 0

for sys in /sys/class/drm/card*-HDMI-*/; do
    [[ -d "${sys}" ]] || continue
    [[ "$(cat "${sys}/status" 2>/dev/null)" == "connected" ]] || continue

    name=$(basename "${sys}")      # e.g. card0-HDMI-A-1
    card=${name%%-*}               # e.g. card0
    dev="/dev/dri/${card}"
    conn_name=${name#*-}           # e.g. HDMI-A-1
    driver=$(basename "$(readlink "${sys}/device/driver" 2>/dev/null)" 2>/dev/null)
    driver=${driver:-i915}

    # Parse proptest output to map the connected connector to its numeric ID
    # and find the "Broadcast RGB" property ID.
    re_connector='^Connector[[:space:]]+([0-9]+)[[:space:]]+\(([^)]+)\)$'
    re_rgb='^[[:space:]]+([0-9]+)[[:space:]]+Broadcast[[:space:]]+RGB:'
    conn_id=""
    prop_id=""
    cur_name=""
    while IFS= read -r line; do
        if [[ "${line}" =~ ${re_connector} ]]; then
            conn_id="${BASH_REMATCH[1]}"
            cur_name="${BASH_REMATCH[2]}"
        elif [[ -n "${conn_id}" && "${line}" =~ ${re_rgb} ]]; then
            if [[ "${cur_name}" == "${conn_name}" ]]; then
                prop_id="${BASH_REMATCH[1]}"
                break
            fi
        fi
    done < <("${PROPTEST}" -M "${driver}" -D "${dev}")

    if [[ -z "${conn_id}" || -z "${prop_id}" ]]; then
        echo "hoodie-rgb: no Broadcast RGB property found for ${conn_name}" >&2
        continue
    fi

    echo "hoodie-rgb: ${conn_name} connector=${conn_id} prop=${prop_id} -> Full"
    "${PROPTEST}" -M "${driver}" -D "${dev}" \
        "${conn_id}" connector "${prop_id}" "${VALUE_FULL}" \
        || echo "hoodie-rgb: failed to set full RGB on ${conn_name}" >&2
done

exit 0
