#!/usr/bin/env bash
set -Eeuo pipefail

app_path="${1:-build/macos/Build/Products/Release/gift.app}"

if [[ ! -d "$app_path" ]]; then
  echo "macOS app bundle does not exist: $app_path" >&2
  exit 66
fi

codesign --deep --force --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
printf 'Ad hoc signed macOS app: %s\n' "$app_path"
