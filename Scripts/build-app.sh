#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
build_dir="$project_dir/Build"
app_dir="$build_dir/CodexQuotaBar.app"

swift build --configuration "$configuration" --package-path "$project_dir"

binary_dir="$(swift build --show-bin-path --configuration "$configuration" --package-path "$project_dir")"
binary_path="$binary_dir/CodexQuotaBar"

if [[ ! -x "$binary_path" ]]; then
    print -u2 "找不到构建产物：$binary_path"
    exit 1
fi

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/CodexQuotaBar"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - "$app_dir" >/dev/null
print "已生成：$app_dir"
