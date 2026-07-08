#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_root="$repo_root/macos/SevenZipMac"
build_root="$app_root/build"
bundle="$build_root/7-Zip Mac.app"
contents="$bundle/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"
engine="$repo_root/CPP/7zip/Bundles/Alone2/b/m_arm64/7zz"

if [ ! -x "$engine" ]; then
  "$repo_root/scripts/build-macos-arm64.sh"
fi

rm -rf "$build_root"
mkdir -p "$macos_dir" "$resources_dir"

swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  "$app_root/Sources/main.swift" \
  -o "$macos_dir/SevenZipMac"

cp "$app_root/Resources/Info.plist" "$contents/Info.plist"
cp "$engine" "$resources_dir/7zz"
chmod +x "$macos_dir/SevenZipMac" "$resources_dir/7zz"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$bundle" >/dev/null
fi

printf '已构建 %s\n' "$bundle"
