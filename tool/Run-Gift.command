#!/bin/zsh
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
app_path="$(/usr/bin/find "$script_directory" -type d -iname 'gift.app' -print -quit)"

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  print -u2 "gift.app was not found beside this launcher."
  print -u2 "Extract the complete ZIP and keep Run-Gift.command with gift.app."
  print -u2 "Launcher folder: $script_directory"
  exit 1
fi

# GitHub downloads carry a quarantine attribute. Remove it only from this app,
# then launch the unsigned local-distribution bundle.
/usr/bin/xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true
/usr/bin/open "$app_path"
