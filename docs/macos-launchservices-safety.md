# macOS LaunchServices Safety Notes

## Incident Summary

During development of the macOS GUI wrapper, an experimental split-handler
design introduced a second archive-opening app named `7-Zip 自动解压.app`.
The goal was to let double-clicking archives extract silently while the main
`7-Zip Mac.app` remained available for archive preview.

That approach was unsafe. Registering two local apps for the same archive file
types and then attempting to change defaults in bulk caused macOS to show many
default-app confirmation prompts. LaunchServices and Finder became unstable on
the affected machine.

## Likely Trigger Chain

1. A helper app was registered as an alternate archive handler.
2. Default archive handlers were changed repeatedly for many UTIs and filename
   extensions.
3. Some attempts used LaunchServices APIs, and later attempts edited
   `~/Library/Preferences/com.apple.LaunchServices*` directly.
4. The user saw repeated prompts asking whether to use the helper app or keep
   using the main app.
5. LaunchServices state became inconsistent enough that Finder/login UI was
   affected until the user moved LaunchServices/Finder preference files aside
   from Recovery.

## Evidence Pattern

In the backed-up `com.apple.launchservices.secure.plist`, archive content types
and filename extensions had many entries pointing at
`com.maiyadiu.sevenzipmac`. Some dynamic UTI entries still pointed at the
experimental `com.maiyadiu.sevenzipautoextractor`, matching the repeated macOS
choice prompts.

## Safety Rules

- Do not create a second app solely to split double-click and preview behavior.
- Do not batch-edit LaunchServices defaults for many archive UTIs.
- Do not directly edit `~/Library/Preferences/com.apple.LaunchServices*` from
  install scripts.
- Do not call `LSSetDefaultRoleHandlerForContentType` in loops for broad file
  type sets.
- Do not run `lsregister` repeatedly during normal install flows.
- Do not kill `lsd` as part of an app installer or verification script.
- Treat Finder Services / Quick Actions as safer than trying to inject
  top-level right-click menus without a proper Finder Sync extension.
- For local prototypes, set default openers manually through Finder Get Info.

## Current Safe Design

- Only one visible app is installed: `7-Zip Mac.app`.
- Double-click behavior is handled by the main app's file-open event.
- Archive preview is exposed through Finder Services as
  `7-Zip：查看压缩包内容`.
- Compression choices are exposed through Finder Services:
  `7-Zip：压缩为 7z`, `7-Zip：极限压缩为 7z`, and `7-Zip：压缩为 zip`.
- Install scripts copy the app only; they do not mutate LaunchServices defaults.
