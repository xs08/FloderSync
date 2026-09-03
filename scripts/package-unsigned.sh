#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data_path="$project_root/build/UnsignedDistributionDerivedData"
distribution_path="$project_root/dist"
built_app="$derived_data_path/Build/Products/Release/FloderSync.app"

/usr/bin/xcodebuild \
  -quiet \
  -project "$project_root/floderSync.xcodeproj" \
  -scheme floderSync \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  clean build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO

/usr/bin/codesign --verify --deep --strict --verbose=2 "$built_app"

binary_architectures="$(/usr/bin/lipo -archs "$built_app/Contents/MacOS/FloderSync")"
for required_architecture in arm64 x86_64; do
  if [[ " $binary_architectures " != *" $required_architecture "* ]]; then
    echo "Missing required architecture: $required_architecture"
    exit 1
  fi
done

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$built_app/Contents/Info.plist")"
archive_path="$distribution_path/FloderSync-$version-macOS-universal-unsigned.zip"

/bin/mkdir -p "$distribution_path"
if [[ -e "$archive_path" ]]; then
  /bin/rm -f "$archive_path"
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$built_app" "$archive_path"

verification_path="$(/usr/bin/mktemp -d /tmp/FloderSync-package.XXXXXX)"
cleanup() {
  if [[ "$verification_path" == /tmp/FloderSync-package.* ]]; then
    /bin/rm -rf "$verification_path"
  fi
}
trap cleanup EXIT

/usr/bin/ditto -x -k "$archive_path" "$verification_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$verification_path/FloderSync.app"

echo
echo "Created: $archive_path"
echo "Architectures: $binary_architectures"
/usr/bin/shasum -a 256 "$archive_path"
