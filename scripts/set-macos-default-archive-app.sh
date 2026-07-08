#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$HOME/Applications/7-Zip Mac.app"
bundle_id="com.maiyadiu.SevenZipMac"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$app" ]; then
  "$repo_root/scripts/install-macos-gui.sh"
fi

if [ -x "$lsregister" ]; then
  "$lsregister" -f "$app"
fi

swift - "$bundle_id" <<'SWIFT'
import CoreServices
import Foundation
import UniformTypeIdentifiers

let bundleId = CommandLine.arguments[1] as CFString
let extensions = [
  "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz",
  "zst", "tzst", "cab", "iso", "dmg", "wim", "esd"
]

var failures: [String] = []

for ext in extensions {
  guard let type = UTType(filenameExtension: ext) else {
    failures.append("\(ext): 无法识别文件类型")
    continue
  }

  let status = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, bundleId)
  if status != noErr {
    failures.append("\(ext): \(type.identifier) 设置失败，状态码 \(status)")
  }
}

if failures.isEmpty {
  print("已把常见压缩包的默认打开方式设置为 7-Zip Mac。")
} else {
  print("部分文件类型设置失败：")
  for failure in failures {
    print("- \(failure)")
  }
  exit(1)
}
SWIFT

