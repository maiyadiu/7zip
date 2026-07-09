#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle="$repo_root/macos/SevenZipMac/build/7-Zip Mac.app"
install_dir="$HOME/Applications"
installed_app="$install_dir/7-Zip Mac.app"
support_helper="$HOME/Library/Application Support/7-Zip Mac/7-Zip 自动解压.app"
legacy_app="$install_dir/SevenZip Mac.app"

if [ ! -d "$bundle" ]; then
  "$repo_root/scripts/build-macos-gui.sh"
fi

mkdir -p "$install_dir"
rm -rf "$installed_app"
rm -rf "$legacy_app"
rm -rf "$support_helper"
cp -R "$bundle" "$installed_app"

rm -rf "$bundle"

printf '已安装 %s\n' "$installed_app"
printf '本安装脚本不会修改默认打开方式，也不会触发默认应用确认框。\n'
printf '右键服务通常会在打开一次应用后出现在 Finder 的服务/快速操作菜单中。\n'
