#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Stage variant-scoped files into the image:
#   files/<variant>/              → /  (rsync overlay)
#   ujust/<variant>/              → /usr/share/ublue-os/just/60-custom.just
#   flatpaks/<variant>.preinstall → /usr/share/flatpak/preinstall.d/
###############################################################################

echo "::group:: Copy Custom Files"

IFS='-' read -ra FLAVOR_PARTS <<<"${IMAGE_FLAVOR}"
VARIANTS=(main)
for variant in "${FLAVOR_PARTS[@]}"; do
    [[ ${variant} == "main" ]] || VARIANTS+=("${variant}")
done

for variant in "${VARIANTS[@]}"; do
    if [[ -d "/ctx/files/${variant}" ]]; then
        echo "Copying files for: ${variant}"
        rsync -rvKl "/ctx/files/${variant}/" /
    fi
done

# Consolidate Just files into the ublue-os custom recipe location
mkdir -p /usr/share/ublue-os/just/
for variant in "${VARIANTS[@]}"; do
    if [[ -d "/ctx/ujust/${variant}" ]]; then
        echo "Installing ujust recipes for: ${variant}"
        find "/ctx/ujust/${variant}" -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just
    fi
done

# Stage Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
for variant in "${VARIANTS[@]}"; do
    if [[ -f "/ctx/flatpaks/${variant}.preinstall" ]]; then
        echo "Installing Flatpak preinstall for: ${variant}"
        cp "/ctx/flatpaks/${variant}.preinstall" "/usr/share/flatpak/preinstall.d/hoodie-${variant}.preinstall"
    fi
done

echo "::endgroup::"

echo "::group:: Register Custom XKB Layout"

# Register the hoodie layout (symbols/hoodie) so GNOME/KDE can select it.
# Inject at build time so the entry tracks the xkeyboard-config version in
# the base image. Files with the name changed by a future include would
# otherwise be clobbered.
if [[ -f /usr/share/X11/xkb/symbols/hoodie ]]; then
    for rules in /usr/share/X11/xkb/rules/evdev.xml /usr/share/X11/xkb/rules/base.xml; do
        if [[ -f "${rules}" ]]; then
            python3 - "${rules}" <<'PYEOF'
import sys

path = sys.argv[1]
entry = """    <layout>
      <configItem>
        <name>hoodie</name>
        <shortDescription>en</shortDescription>
        <description>English (Colemak-DH Wide ISO Symbols)</description>
        <languageList>
          <iso639Id>eng</iso639Id>
        </languageList>
      </configItem>
      <variantList/>
    </layout>
"""
with open(path) as fh:
    content = fh.read()
if "<name>hoodie</name>" in content:
    print(f"{path}: hoodie already registered")
    sys.exit(0)
marker = "  </layoutList>"
if marker not in content:
    print(f"{path}: </layoutList> marker not found", file=sys.stderr)
    sys.exit(1)
content = content.replace(marker, entry + marker)
with open(path, "w") as fh:
    fh.write(content)
print(f"{path}: registered hoodie layout")
PYEOF
        fi
    done
else
    echo "Symbols file missing; skipping XKB registration"
fi

echo "::endgroup::"

echo "Custom file staging complete!"
