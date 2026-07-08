#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$repo_root/CPP/7zip/Bundles/Alone2"
output="$build_dir/b/m_arm64/7zz"

jobs=${JOBS:-}
if [ -z "$jobs" ]; then
  jobs=$(sysctl -n hw.ncpu 2>/dev/null || printf '4')
fi

cd "$build_dir"
make -j"$jobs" -f ../../cmpl_mac_arm64.mak "$@"

printf '\nBuilt %s\n' "$output"
file "$output"

