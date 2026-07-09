#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$HOME/Applications/7-Zip Mac.app"
old_support_helper="$HOME/Library/Application Support/7-Zip Mac/7-Zip 自动解压.app"

if [ ! -d "$app" ]; then
  printf '还没有安装 %s\n' "$app" >&2
  printf '请先运行：%s/scripts/install-macos-gui.sh\n' "$repo_root" >&2
  exit 1
fi

rm -rf "$old_support_helper"

cat <<EOF
为避免触发 macOS 默认打开方式确认风暴，本脚本不再自动修改
~/Library/Preferences/com.apple.LaunchServices*。

请用 macOS 图形界面设置默认打开方式：

1. 在 Finder 里选中一个 .7z、.zip 或 .rar 压缩包。
2. 按 Command-I 打开“显示简介”。
3. 在“打开方式”里选择：
   $app
4. 点击“全部更改...”。
5. 如 macOS 弹出确认，只确认这一次。

右键菜单动作来自 App 内置 Finder Services：
- 7-Zip：查看压缩包内容
- 7-Zip：解压到当前文件夹
- 7-Zip：解压到同名文件夹
- 7-Zip：压缩为 7z
- 7-Zip：极限压缩为 7z
- 7-Zip：压缩为 zip
EOF
