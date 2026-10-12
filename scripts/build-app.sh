#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --build-system native -c release --product PrimeSieve
binary_directory="$(swift build --build-system native -c release --show-bin-path)"
mkdir -p "$project_root/dist"
output_app="$project_root/dist/PrimeSieve.app"
# Assemble and verify a fresh bundle; never merge resources into an older build.
staging_directory="$(mktemp -d "$project_root/dist/build-app.XXXXXX")"
cleanup() {
    if [[ -e "$staging_directory/previous.app" && ! -e "$output_app" ]]; then
        mv "$staging_directory/previous.app" "$output_app" || return
    fi
    rm -rf "$staging_directory"
}
trap cleanup EXIT
app_directory="$staging_directory/PrimeSieve.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/PrimeSieve" "$app_directory/Contents/MacOS/PrimeSieve"
cp -R "$binary_directory/PrimeSieve_PrimeSieveCore.bundle" "$app_directory/Contents/Resources/"
"$project_root/scripts/build-icon.sh" "$app_directory/Contents/Resources/AppIcon.icns"
cat > "$app_directory/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PrimeSieve</string>
<key>CFBundleIdentifier</key><string>us.rickard.PrimeSieve</string>
<key>CFBundleName</key><string>PrimeSieve</string>
<key>CFBundleDisplayName</key><string>PrimeSieve</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
signing_identity="${SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$app_directory"
else
    # Public distribution requires Developer ID, hardened runtime, and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_directory"
    signature_details="$(codesign --display --verbose=4 "$app_directory" 2>&1)"
    if [[ "$signature_details" != *"Authority=Developer ID Application:"* ]]; then
        print -u2 -- "Public builds require a Developer ID Application certificate."
        exit 1
    fi
fi
codesign --verify --deep --strict "$app_directory"
# Keep the previous build available for rollback until the new bundle is in place.
if [[ -e "$output_app" ]]; then
    mv "$output_app" "$staging_directory/previous.app"
fi
mv "$app_directory" "$output_app"
printf '%s\n' "$output_app"
