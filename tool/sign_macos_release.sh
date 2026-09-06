#!/usr/bin/env bash
set -Eeuo pipefail

app_path="${1:-build/macos/Build/Products/Release/gift.app}"

if [[ ! -d "$app_path" ]]; then
  echo "macOS app bundle does not exist: $app_path" >&2
  exit 66
fi
codesign --deep --force --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
if [[ "$signature_details" != *"Signature=adhoc"* ]]; then
  echo "macOS app does not have an ad hoc signature: $app_path" >&2
  echo "$signature_details" >&2
  exit 65
fi
printf 'Ad hoc signed macOS app: %s\n' "$app_path"
