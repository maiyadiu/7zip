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
drop, compression, extraction, optional password input, and Finder Services
entries for local use. The default-app script registers common archive formats
so double-clicking archives auto-extracts them to the archive's containing
folder via `7-Zip Mac`.

Finder Services provide local right-click actions:
`7-Zip：解压到当前文件夹`, `7-Zip：解压到同名文件夹`,
`7-Zip：压缩为 7z`, and `7-Zip：压缩为 zip`. macOS usually shows these under
Finder's Services or Quick Actions submenu unless a Finder Sync extension is
added later.

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
