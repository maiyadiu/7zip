#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle="$repo_root/macos/SevenZipMac/build/7-Zip Mac.app"
install_dir="$HOME/Applications"
installed_app="$install_dir/7-Zip Mac.app"
legacy_app="$install_dir/SevenZip Mac.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
pbs="/System/Library/CoreServices/pbs"

if [ ! -d "$bundle" ]; then
  "$repo_root/scripts/build-macos-gui.sh"
fi

mkdir -p "$install_dir"
rm -rf "$installed_app"
rm -rf "$legacy_app"
cp -R "$bundle" "$installed_app"

if [ -x "$lsregister" ]; then
  "$lsregister" -f "$installed_app"
fi

if [ -x "$pbs" ]; then
  "$pbs" -flush
fi

rm -rf "$bundle"

printf '已安装 %s\n' "$installed_app"
printf '请先打开一次应用；如果 macOS 询问是否启用 Finder 服务，请允许。\n'
