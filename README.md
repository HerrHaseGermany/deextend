# Deextend

**Version 0.1.0** · A native macOS menu bar app for pausing external displays while keeping your USB-C hub connected.

Deextend virtually disconnects external displays from your Mac. Switch your monitor to another input and keep working on your MacBook while the hub and its other devices stay connected.

## Features

- **Left-click:** Pause external displays together, or reconnect paused displays.
- **Right-click:** Open controls directly below the menu bar icon and manage individual displays.
- **Connection popup:** A separate popup with a Reconnect button when a paused display is plugged in again. It also appears if the display stays virtually disconnected, and dismisses itself after 20 seconds.
- **English and German:** Selected automatically using your macOS language preferences, with English as the fallback.
- **Optional launch at login:** Enable Launch at login in the controls.

Pause bars appear inside the display icon while display pause is active. The built-in display is never disabled: keep your MacBook open with its display active when disconnecting external displays. Quitting normally reconnects the displays paused by Deextend.

## Requirements

- An Apple Silicon Mac running macOS 13 or later.
- An active built-in display and at least one external display.
- To build: Xcode or a suitable Swift toolchain; Python 3 to run the tests.

Deextend uses private macOS display interfaces. A macOS update may change their behavior. The app is not notarized; local builds are signed with a developer certificate available on your Mac.

## Build and run

```sh
./scripts/build.sh
open build/Deextend.app
```

The build script uses a valid **Apple Development** identity from your local keychain by default. To choose between multiple identities or use a different certificate:

```sh
CODE_SIGN_IDENTITY="Your codesigning identity name or SHA-1" ./scripts/build.sh
```

Run `security find-identity -v -p codesigning` to list available identities. The build fails if the certificate is unavailable; it never falls back to ad-hoc signing automatically. The signature is verified before copying the app into the project directory.

For everyday use, copy the app to `~/Applications` or `/Applications` and run only that copy. Quit a running version normally before replacing it.

## Usage

1. Keep your MacBook open and connect the external display.
2. Left-click the menu bar icon to virtually disconnect the external display.
3. Switch the monitor to another input.
4. To return, select your Mac's input on the monitor and click the icon again, or choose **Reconnect** in the connection popup.

Display pause is remembered per display while the app is running. Other displays connected for the first time are not paused automatically. If macOS reactivates a paused display, Deextend attempts to disconnect it again. Automatic retries stop after three attempts within one minute. Connection popups do not require macOS notification permissions.

## Limitations and recovery

- Windows may move when a display is disconnected; their original positions are not restored.
- Deextend does not switch monitor inputs or disable other hub devices.
- AirPlay, DisplayLink, and other specialized display adapters have not been verified. Testing covered an Apple M3 running macOS 27.2 with a Samsung LU28R55. The connection popup after physically unplugging and reconnecting the hub was confirmed on that setup. A complete sleep/wake cycle has not yet been confirmed.
- A display may remain disconnected after a crash or force quit. Reopen Deextend and choose **Connect**, reconnect the hub, or restart macOS.
- Identical monitors without unique serial numbers may be difficult to distinguish after changing ports.

Device names and recovery information are stored locally in the `de.christianraudzis.deextend.display-cache` preferences domain. Before each change, Deextend resolves the target against the current display list rather than passing an unchecked cached display ID to macOS.

## Development

```sh
./scripts/test.sh
```

The tests cover display safety rules, reconnection, physical connection events while displays remain offline, translations, and language fallback. They do not change the actual display configuration.

With the app closed, read-only diagnostics and an optional hardware test are also available:

```sh
# Read-only diagnostics
build/Deextend.app/Contents/MacOS/Deextend --diagnose

# Briefly disconnects the first active external display, then reconnects it
build/Deextend.app/Contents/MacOS/Deextend --verify-toggle
```

To add a language, copy the English translation file to `Resources/<language-code>.lproj/Localizable.strings`, translate its values, and preserve the keys and format placeholders. The build and tests pick up additional language directories automatically.

The implementation uses CoreGraphics configuration transactions, dynamically resolved private SkyLight symbols, and IOKit connection events. Background on these interfaces: [Apple display configuration](https://developer.apple.com/documentation/coregraphics/cgdisplayconfigref) and [MacDisplay](https://github.com/jjongkwann/MacDisplay). The implementation is independent; no source code from other apps was copied.

## License and changes

[MIT License](LICENSE) · [Changelog](CHANGELOG.md)
