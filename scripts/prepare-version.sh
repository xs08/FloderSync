#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
version_file="$project_root/Config/Version.xcconfig"

usage() {
  echo "Usage: $0 [x.y.z]"
  echo "       $0 --current"
  echo "       $0 --next x.y.z"
}

is_semantic_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

next_minor_version() {
  local current_version="$1"
  local major
  local minor

  if ! is_semantic_version "$current_version"; then
    echo "Invalid version '$current_version'. Expected x.y.z with numeric components." >&2
    exit 1
  fi

  IFS=. read -r major minor _ <<< "$current_version"
  echo "$major.$((10#$minor + 1)).0"
}

current_version="$(/usr/bin/awk -F ' *= *' '$1 == "MARKETING_VERSION" { print $2 }' "$version_file")"
if ! is_semantic_version "$current_version"; then
  echo "Invalid MARKETING_VERSION in $version_file: '$current_version'" >&2
  exit 1
fi

if [[ "${1:-}" == "--current" ]]; then
  if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
  fi
  echo "$current_version"
  exit 0
fi

if [[ "${1:-}" == "--next" ]]; then
  if [[ $# -ne 2 ]]; then
    usage >&2
    exit 1
  fi
  next_minor_version "$2"
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  target_version="$1"
  if ! is_semantic_version "$target_version"; then
    echo "Invalid version '$target_version'. Expected x.y.z with numeric components." >&2
    exit 1
  fi
else
  target_version="$(next_minor_version "$current_version")"
fi

temporary_file="$(/usr/bin/mktemp "$version_file.XXXXXX")"
cleanup() {
  if [[ -e "$temporary_file" ]]; then
    /bin/rm -f "$temporary_file"
  fi
}
trap cleanup EXIT

/usr/bin/awk -v target_version="$target_version" '
  $1 == "MARKETING_VERSION" { print "MARKETING_VERSION = " target_version; next }
  { print }
' "$version_file" > "$temporary_file"
/bin/mv "$temporary_file" "$version_file"

echo "$target_version"
