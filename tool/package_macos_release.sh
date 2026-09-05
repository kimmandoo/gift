#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

release_tag="${GIFT_RELEASE_TAG:-}"
if [[ ! "$release_tag" =~ ^release-v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "GIFT_RELEASE_TAG must be a release-v<semver> tag." >&2
  exit 64
fi
version="${release_tag#release-v}"
output_directory="${GIFT_RELEASE_OUTPUT_DIR:-dist}"
mkdir -p "$output_directory"
architecture="${RUNNER_ARCH:-$(uname -m)}"
case "$architecture" in
  X64|x64|X86_64|x86_64|AMD64|amd64) architecture="x64" ;;
  ARM64|arm64|AARCH64|aarch64) architecture="arm64" ;;
  *) echo "Unsupported macOS runner architecture: $architecture" >&2; exit 64 ;;
esac
archive="$output_directory/gift-${version}-macos-${architecture}.zip"
rm -f "$archive"

ditto -c -k --sequesterRsrc --keepParent \
  build/macos/Build/Products/Release/gift.app \
  "$archive"
printf 'macOS release archive: %s\n' "$archive"
