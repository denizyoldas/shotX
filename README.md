# shotX

A small macOS menu-bar app for screenshots and screen recordings. Native Swift, zero dependencies.

## Features

- Area, window and fullscreen capture with global hotkeys
- Auto copy to clipboard and save to a folder
- Quick Access preview in the screen corner: copy, save, annotate, pin, drag and drop
- Annotation editor: arrow, rectangle, ellipse, line, freehand, text, highlight, blur/pixelate, counter, crop, undo/redo
- Screen recording to MP4 or GIF, with optional microphone and system audio
- Text recognition (OCR) from a selected area
- Pin a capture to the screen as a floating window

## Default hotkeys

| Action | Keys |
|---|---|
| Capture area | ⌃⌥A |
| Capture window | ⌃⌥W |
| Capture fullscreen | ⌃⌥F |
| Record area | ⌃⌥R |
| Record fullscreen | ⌃⌥⇧R |
| Start/stop recording | ⌃⌥S |
| Capture text (OCR) | ⌃⌥T |

All hotkeys can be changed in Settings. If you assign ⇧⌘3, ⇧⌘4 or ⇧⌘5, shotX turns off macOS's own shortcut for that key while it runs and gives it back when it quits.

## Requirements

- macOS 27, Apple silicon
- Xcode 27 / Swift 6 toolchain

## Build and run

```bash
make run
```

This builds, signs and opens `build/shotX.app`. Other targets:

| Command | Does |
|---|---|
| `make build` | `swift build` (warnings are errors) |
| `make test` | run unit tests (no permissions needed) |
| `make app` | build and assemble the signed `.app` bundle |
| `make install` | copy the bundle to `~/Applications` (needed for launch at login) |
| `make check` | build, test and file-length check |

Always launch the bundle (`make run`), not the bare binary in `.build/`: permissions are tied to the signed app.

### Signing

`scripts/bundle.sh` signs with the identity whose SHA-1 is in `signing.local` (gitignored). If that file is missing and exactly one code-signing identity is installed, it is picked automatically. Otherwise the app is signed ad hoc, and macOS will ask for Screen Recording permission again after every build.

### Permissions

- **Screen Recording**: required for every capture and recording
- **Microphone**: only if you turn on microphone recording

## Project layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the code structure and [docs/ROADMAP.md](docs/ROADMAP.md) for the test plan and what is out of scope.

## License

[MIT](LICENSE)
