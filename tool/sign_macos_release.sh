#!/usr/bin/env bash
set -Eeuo pipefail

app_path="${1:-build/macos/Build/Products/Release/gift.app}"
: "${MACOS_CERTIFICATE_BASE64:?MACOS_CERTIFICATE_BASE64 is required for a public release}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is required for a public release}"
: "${MACOS_KEYCHAIN_PASSWORD:?MACOS_KEYCHAIN_PASSWORD is required for a public release}"
: "${MACOS_SIGNING_IDENTITY:?MACOS_SIGNING_IDENTITY is required for a public release}"
: "${APPLE_ID:?APPLE_ID is required for notarization}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for notarization}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required for notarization}"

if [[ ! -d "$app_path" ]]; then
  echo "macOS app bundle does not exist: $app_path" >&2
  exit 66
fi

certificate_path="${RUNNER_TEMP:-/tmp}/gift-signing.p12"
keychain_path="${RUNNER_TEMP:-/tmp}/gift-signing.keychain-db"
notary_archive="${RUNNER_TEMP:-/tmp}/gift-notary.zip"
cleanup() {
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -f "$certificate_path" "$notary_archive"
}
trap cleanup EXIT

printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 -D > "$certificate_path"
security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$keychain_path"
security import "$certificate_path" -P "$MACOS_CERTIFICATE_PASSWORD" \
  -A -t cert -f pkcs12 -k "$keychain_path"
security list-keychains -d user -s "$keychain_path"
security default-keychain -s "$keychain_path"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$MACOS_KEYCHAIN_PASSWORD" "$keychain_path"
codesign --deep --force --options runtime --timestamp \
  --sign "$MACOS_SIGNING_IDENTITY" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_archive"
xcrun notarytool submit "$notary_archive" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
printf 'Signed, notarized, and stapled macOS app: %s\n' "$app_path"
