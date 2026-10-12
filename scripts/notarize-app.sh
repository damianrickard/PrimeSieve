#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
profile="${1:?Usage: notarize-app.sh KEYCHAIN_PROFILE [APP_PATH]}"
app_path="${2:-$project_root/dist/PrimeSieve.app}"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Fail before uploading if this is a local/development build or lacks required protections.
codesign --verify --deep --strict "$app_path"
signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
if [[ "$signature_details" != *"Authority=Developer ID Application:"* ||
      "$signature_details" != *"(runtime)"* || "$signature_details" != *"Timestamp="* ]]; then
    print -u2 -- "Build with a Developer ID Application identity, hardened runtime and secure timestamp first."
    exit 1
fi

# Preserve submission details and work on a copy so the input app is never modified.
mkdir -p "$project_root/dist"
notary_workspace="$(mktemp -d "$project_root/dist/notarization.XXXXXX")"
print -- "Notarization files: $notary_workspace"
app_copy="$notary_workspace/PrimeSieve.app"
ditto "$app_path" "$app_copy"
ditto -c -k --sequesterRsrc --keepParent "$app_copy" "$notary_workspace/submission.zip"
if ! xcrun notarytool submit "$notary_workspace/submission.zip" --keychain-profile "$profile" \
    --wait --timeout 20m --output-format json > "$notary_workspace/submission.json"; then
    print -u2 -- "Submission did not finish successfully. Inspect submission.json; an uploaded job may still be processing."
    exit 1
fi
notary_status="$(plutil -extract status raw -o - "$notary_workspace/submission.json")"
if [[ "$notary_status" != "Accepted" ]]; then
    submission_id="$(plutil -extract id raw -o - "$notary_workspace/submission.json")"
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$notary_workspace/notary-log.json"
    print -u2 -- "Apple returned $notary_status. See notary-log.json; no release archive was produced."
    exit 1
fi

# Staple the approval ticket before making the archive people will download.
xcrun stapler staple "$app_copy"
xcrun stapler validate "$app_copy"
codesign --verify --deep --strict "$app_copy"
spctl --assess --type execute --verbose=2 "$app_copy"
app_version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_copy/Contents/Info.plist")"
app_build="$(plutil -extract CFBundleVersion raw -o - "$app_copy/Contents/Info.plist")"
architecture="$(lipo -archs "$app_copy/Contents/MacOS/PrimeSieve" | tr ' ' '-')"
archive_name="PrimeSieve-v${app_version}-build${app_build}-macos-${architecture}-notarized.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_copy" "$notary_workspace/$archive_name"
(cd "$notary_workspace" && shasum -a 256 "$archive_name" > "$archive_name.sha256")
print -- "Verified notarized download: $notary_workspace/$archive_name"
