#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$HOME/Applications/7-Zip Mac.app"
support_helper="$HOME/Library/Application Support/7-Zip Mac/7-Zip 自动解压.app"
bundle_id="com.maiyadiu.SevenZipMac"

if [ ! -d "$app" ]; then
  "$repo_root/scripts/install-macos-gui.sh"
fi

rm -rf "$support_helper"

swift - "$bundle_id" <<'SWIFT'
import Foundation

let bundleId = CommandLine.arguments[1]
let bundleIdForPreferences = bundleId.lowercased()

let contentTypes = [
  "org.7-zip.7-zip-archive",
  "public.zip-archive",
  "com.rarlab.rar-archive",
  "public.tar-archive",
  "org.gnu.gnu-zip-archive",
  "org.gnu.gnu-zip-tar-archive",
  "public.bzip2-archive",
  "public.tar-bzip2-archive",
  "org.tukaani.xz-archive",
  "org.tukaani.tar-xz-archive",
  "com.maiyadiu.7zip.archive.zstd",
  "com.microsoft.cab",
  "public.iso-image",
  "com.apple.disk-image-udif",
  "com.maiyadiu.7zip.archive.7z",
  "com.maiyadiu.7zip.archive.rar"
]

let filenameExtensions = [
  "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz",
  "zst", "tzst", "cab", "iso", "dmg", "wim", "esd"
]

var failures: [String] = []

let preferencesURL = URL(fileURLWithPath: NSHomeDirectory())
  .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")

do {
  var root: [String: Any] = [:]
  if FileManager.default.fileExists(atPath: preferencesURL.path) {
    var format = PropertyListSerialization.PropertyListFormat.xml
    let data = try Data(contentsOf: preferencesURL)
    root = try PropertyListSerialization.propertyList(
      from: data,
      options: [.mutableContainersAndLeaves],
      format: &format
    ) as? [String: Any] ?? [:]
  }

  var handlers = root["LSHandlers"] as? [[String: Any]] ?? []
  let now = Date().timeIntervalSinceReferenceDate

  for contentType in Set(contentTypes) {
    if let index = handlers.firstIndex(where: { ($0["LSHandlerContentType"] as? String) == contentType }) {
      handlers[index]["LSHandlerRoleAll"] = bundleIdForPreferences
      handlers[index]["LSHandlerModificationDate"] = now
      handlers[index]["LSHandlerPreferredVersions"] = ["LSHandlerRoleAll": "-"]
    } else {
      handlers.append([
        "LSHandlerContentType": contentType,
        "LSHandlerRoleAll": bundleIdForPreferences,
        "LSHandlerModificationDate": now,
        "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"]
      ])
    }
  }

  for filenameExtension in Set(filenameExtensions) {
    let matchesExtension: ([String: Any]) -> Bool = { handler in
      (handler["LSHandlerContentTag"] as? String) == filenameExtension
        && (handler["LSHandlerContentTagClass"] as? String) == "public.filename-extension"
    }

    if let index = handlers.firstIndex(where: matchesExtension) {
      handlers[index]["LSHandlerRoleAll"] = bundleIdForPreferences
      handlers[index]["LSHandlerModificationDate"] = now
      handlers[index]["LSHandlerPreferredVersions"] = ["LSHandlerRoleAll": "-"]
    } else {
      handlers.append([
        "LSHandlerContentTag": filenameExtension,
        "LSHandlerContentTagClass": "public.filename-extension",
        "LSHandlerRoleAll": bundleIdForPreferences,
        "LSHandlerModificationDate": now,
        "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"]
      ])
    }
  }

  root["LSHandlers"] = handlers
  let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
  try FileManager.default.createDirectory(
    at: preferencesURL.deletingLastPathComponent(),
    withIntermediateDirectories: true,
    attributes: nil
  )
  try data.write(to: preferencesURL, options: .atomic)
} catch {
  failures.append("LaunchServices 偏好写入失败：\(error.localizedDescription)")
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

killall cfprefsd >/dev/null 2>&1 || true

swift - "$bundle_id" <<'SWIFT'
import Foundation

let bundleId = CommandLine.arguments[1].lowercased()
let contentTypes = [
  "org.7-zip.7-zip-archive",
  "public.zip-archive",
  "com.rarlab.rar-archive",
  "public.tar-archive",
  "org.gnu.gnu-zip-archive"
]
var failures: [String] = []

let preferencesURL = URL(fileURLWithPath: NSHomeDirectory())
  .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
let data = try Data(contentsOf: preferencesURL)
let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
let handlers = root?["LSHandlers"] as? [[String: Any]] ?? []

for contentType in contentTypes {
  let handler = handlers.last { ($0["LSHandlerContentType"] as? String) == contentType }?["LSHandlerRoleAll"] as? String
  if handler?.lowercased() != bundleId {
    failures.append("\(contentType): 当前为 \(handler ?? "无")")
  }
}

if failures.isEmpty {
  print("已验证 LaunchServices 偏好为 7-Zip Mac。")
} else {
  print("LaunchServices 偏好验证仍未全部生效：")
  for failure in failures {
    print("- \(failure)")
  }
  exit(1)
}
SWIFT
