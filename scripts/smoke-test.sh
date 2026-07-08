#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sevenzip_bin=${SEVENZIP_BIN:-"$repo_root/CPP/7zip/Bundles/Alone2/b/m_arm64/7zz"}

if [ ! -x "$sevenzip_bin" ]; then
  "$repo_root/scripts/build-macos-arm64.sh"
fi

tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$tmp_root/7zip-smoke.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT INT TERM

mkdir -p "$work_dir/in" "$work_dir/out"
printf 'hello 7zip macos arm64\n' > "$work_dir/in/hello.txt"
printf 'unicode filename and content: 中文测试\n' > "$work_dir/in/中文.txt"

cd "$work_dir"
"$sevenzip_bin" a test.7z in >/dev/null
"$sevenzip_bin" t test.7z >/dev/null
"$sevenzip_bin" x test.7z -oout >/dev/null
diff -ru in out/in >/dev/null

printf 'smoke-test-ok: %s\n' "$sevenzip_bin"

