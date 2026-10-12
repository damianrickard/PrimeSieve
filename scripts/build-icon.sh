#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
output="${1:-$project_root/dist/AppIcon.icns}"
icon_workspace="$(mktemp -d "${TMPDIR:-/tmp}/PrimeSieve-icon.XXXXXX")"
trap 'rm -rf "$icon_workspace"' EXIT
iconset="$icon_workspace/AppIcon.iconset"
mkdir -p "$iconset" "${output:h}"

# Generate every standard macOS icon size, including Retina representations.
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_root/Assets/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$project_root/Assets/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$output" "$iconset"
