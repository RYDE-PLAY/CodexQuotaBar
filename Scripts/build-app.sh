#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
build_args=(--configuration "$configuration" --package-path "$project_dir")
if [[ "${2:-}" == "universal" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
build_dir="$project_dir/Build"
app_dir="$build_dir/CodexQuotaBar.app"

swift build "${build_args[@]}"

binary_dir="$(swift build --show-bin-path "${build_args[@]}")"
binary_path="$binary_dir/CodexQuotaBar"

if [[ ! -x "$binary_path" ]]; then
    print -u2 "找不到构建产物：$binary_path"
    exit 1
fi

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/CodexQuotaBar"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/chatgptTemplate@2x.png" "$app_dir/Contents/Resources/"

codesign --force --deep --sign - "$app_dir" >/dev/null
print "已生成：$app_dir"
