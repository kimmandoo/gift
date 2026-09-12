#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

release_tag="${GIFT_RELEASE_TAG:-}"
if [[ -n "$release_tag" && ! "$release_tag" =~ ^release-v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "GIFT_RELEASE_TAG must be a release-v<semver> tag." >&2
  exit 64
fi

output_directory="${GIFT_RELEASE_OUTPUT_DIR:-dist}"
app_path="build/macos/Build/Products/Release/gift.app"
launcher_path="tool/Run-Gift.command"

if [[ ! -d "$app_path" ]]; then
  echo "macOS app bundle does not exist: $app_path" >&2
  exit 66
fi
if [[ ! -f "$launcher_path" ]]; then
  echo "macOS launcher does not exist: $launcher_path" >&2
  exit 66
fi

executable="$app_path/Contents/MacOS/gift"
archs="$(lipo -archs "$executable")"
case " $archs " in
  *" arm64 "*) ;;
  *) echo "The macOS bundle is missing arm64."; exit 65 ;;
esac
case " $archs " in
  *" x86_64 "*) ;;
  *) echo "The macOS bundle is missing x86_64."; exit 65 ;;
esac

mkdir -p "$output_directory"
if [[ -n "$release_tag" ]]; then
  archive="$output_directory/gift-${release_tag#release-v}-macos-universal.app.zip"
else
  archive="$output_directory/gift-macos-universal.app.zip"
fi
rm -f "$archive"

staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
package_directory="$staging_directory/gift-macos-universal"
mkdir -p "$package_directory"
ditto "$app_path" "$package_directory/gift.app"
cp "$launcher_path" "$package_directory/Run-Gift.command"
chmod +x "$package_directory/Run-Gift.command"
ditto -c -k --sequesterRsrc --keepParent \
  "$package_directory" "$archive"
printf 'macOS universal release archive: %s\n' "$archive"
