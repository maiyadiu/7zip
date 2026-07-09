# Local 7-Zip Development Notes

## Status

- Source: official `ip7z/7zip` GitHub repository.
- Version: `26.02`, released 2026-06-25.
- Local branch: `codex-macos-custom`.
- Host target: macOS arm64.
- Primary local binary: `CPP/7zip/Bundles/Alone2/b/m_arm64/7zz`.
- Current customization: the `Alone2` build defines
  `Z7_LOCAL_BUILD_LABEL="codex-macos-custom"`, so the console banner clearly
  identifies this local build.
- macOS GUI: `macos/SevenZipMac` builds a local-use Chinese AppKit shell around
  the bundled `7zz` engine.

## Build

```sh
scripts/build-macos-arm64.sh
```

The script builds `CPP/7zip/Bundles/Alone2`, which produces the standalone
`7zz` command-line binary with broad archive format support.

## Verify

```sh
scripts/smoke-test.sh
```

The smoke test creates a small archive, tests it, extracts it, and compares the
extracted files with the original files, including a Unicode filename.

## macOS GUI

```sh
scripts/build-macos-gui.sh
scripts/install-macos-gui.sh
scripts/set-macos-default-archive-app.sh
```

The GUI app is built at `macos/SevenZipMac/build/7-Zip Mac.app` and installed to
`~/Applications/7-Zip Mac.app`. It provides a Chinese interface with drag and
drop, compression, extraction, hierarchical archive-content preview, optional
password input, and Finder Services entries for local use.

The app can be set as the default archive opener through Finder's "Get Info"
panel. When the app is launched by double-clicking an archive, it shows a small
progress window and extracts the archive to its containing folder without
showing the main operation window or opening a Finder result window. The main
app remains the manual viewer and operation surface when launched normally or
through the archive-preview Finder Service.

`scripts/set-macos-default-archive-app.sh` intentionally does not edit
LaunchServices preferences. It only prints manual setup steps and removes the
old experimental helper copy if present. Do not automate default-app changes by
batch editing `~/Library/Preferences/com.apple.LaunchServices*`, calling
`LSSetDefaultRoleHandlerForContentType` in loops, repeatedly running
`lsregister`, or killing `lsd`; those actions can trigger repeated macOS
confirmation prompts and destabilize Finder/login state.

Finder Services provide local right-click actions:
`7-Zip：查看压缩包内容`, `7-Zip：解压到当前文件夹`,
`7-Zip：解压到同名文件夹`, `7-Zip：压缩为 7z`,
`7-Zip：极限压缩为 7z`, `7-Zip：压缩为 zip`, and
`7-Zip：服务端打包为 tar.gz`. macOS usually shows these under Finder's
Services or Quick Actions submenu unless a Finder Sync extension is added later.

The current macOS interaction contract is:

1. Double-click an archive: compact progress-window extraction through
   `7-Zip Mac.app`.
2. Right-click an archive and choose `7-Zip：查看压缩包内容`: open the main app and
   show an expandable archive tree across the full lower workspace. Folders can
   be expanded with the disclosure control or by double-clicking, without
   extracting the archive first. The selected-file area is intentionally compact:
   paths appear as a one-line summary so the archive preview remains the primary
   working surface.
3. Right-click files or folders and choose `7-Zip：极限压缩为 7z`: create a 7z
   archive with LZMA2, maximum compression level, 256 MB dictionary, maximum fast
   bytes, solid mode, and multithreading enabled.
4. Right-click a game server directory such as `jxser` and choose
   `7-Zip：服务端打包为 tar.gz`: create a Linux-friendly `tar.gz` package by
   first writing a tar archive with relative paths, then gzip-compressing that
   tar file. The service filters macOS metadata files such as `.DS_Store`,
   `._*`, and `__MACOSX`, while preserving real UTF-8 filenames for transfer
   back to the remote game server.

For `.tar.gz` / `.tgz` archives, preview and extraction are recursive: the app
streams the outer gzip layer into the inner tar reader, so the UI shows the real
`jxser/...` tree and extraction produces the directory contents directly rather
than leaving a standalone `.tar` file.

`macos/SevenZipMac/Resources/AppIcon.icns` is bundled as the app icon. The
installer removes the temporary build app after copying it to `~/Applications`
so Finder normally shows only one `7-Zip Mac.app`.

## Product Judgment

7-Zip is a strong default choice when the priority is open source availability,
high compression ratio, broad archive compatibility, AES-256 support, and a
maintainable command-line core. It is not universally the best tool for every
case: zstd/lz4 can be better for speed-first workflows, platform archive tools
can be better for native UX, and dedicated GUI apps can be better for casual
macOS users.

## Safe Customization Areas

- Build and packaging scripts for macOS.
- Command-line defaults and user-facing messages.
- Wrapper commands for common archive workflows.
- Format policy toggles, such as excluding RAR code with documented license
  implications.

Avoid changing codec internals until a benchmark and compatibility target is
defined.
