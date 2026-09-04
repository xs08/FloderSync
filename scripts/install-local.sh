#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data_path="$project_root/build/LocalInstallDerivedData"
built_app="$derived_data_path/Build/Products/Release/FloderSync.app"
installed_app="/Applications/FloderSync.app"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [x.y.z]" >&2
  exit 1
fi

if /usr/bin/pgrep -x FloderSync >/dev/null; then
  echo "FloderSync is running. Quit it from the menu bar, then run this script again."
  exit 1
fi

if [[ $# -eq 1 ]]; then
  app_version="$("$project_root/scripts/prepare-version.sh" "$1")"
else
  app_version="$("$project_root/scripts/prepare-version.sh")"
fi
echo "Building FloderSync $app_version"

/usr/bin/xcodebuild \
  -project "$project_root/floderSync.xcodeproj" \
  -scheme floderSync \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  build

install_workspace="$(/usr/bin/mktemp -d /Applications/.FloderSync-install.XXXXXX)"
staged_app="$install_workspace/FloderSync.app"
previous_app="$install_workspace/Previous-FloderSync.app"

cleanup() {
  if [[ "$install_workspace" == /Applications/.FloderSync-install.* ]]; then
    /bin/rm -rf "$install_workspace"
  fi
}
trap cleanup EXIT

/usr/bin/ditto "$built_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

if [[ -e "$installed_app" ]]; then
  /bin/mv "$installed_app" "$previous_app"
fi

if ! /bin/mv "$staged_app" "$installed_app"; then
  if [[ -e "$previous_app" ]]; then
    /bin/mv "$previous_app" "$installed_app"
  fi
  exit 1
fi

/usr/bin/open "$installed_app"

echo "Installed and launched FloderSync $app_version at $installed_app"
