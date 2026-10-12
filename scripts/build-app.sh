#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --build-system native -c release --product PrimeSieve
binary_directory="$(swift build --build-system native -c release --show-bin-path)"
app_directory="$project_root/dist/PrimeSieve.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/PrimeSieve" "$app_directory/Contents/MacOS/PrimeSieve"
cp -R "$binary_directory/PrimeSieve_PrimeSieveCore.bundle" "$app_directory/Contents/Resources/"
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
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_directory"
printf '%s\n' "$app_directory"
