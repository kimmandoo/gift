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
archive="$output_directory/gift-${version}-linux-x64.tar.gz"
rm -f "$archive"

tar -C build/linux/x64/release/bundle -czf "$archive" .
printf 'Linux release archive: %s\n' "$archive"
