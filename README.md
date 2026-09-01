# Nimbus

Temporary macOS 14 Swift scaffold for a native menu-bar app.

- AppKit `NSApplicationDelegate` owns the status item and menu.
- `NSWindow` hosts the native main window shell.
- SwiftUI supplies the content and `WindowGroup` scene.

`Package.swift` is the canonical SwiftPM build/test entry point. `Nimbus.xcodeproj`
is preserved as the optional Xcode development and debugging entry point.

## Build

```sh
swift build
```

## Test

```sh
swift test
```
