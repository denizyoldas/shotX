# Architecture

Everything is `internal` to `ShotXKit` (only `AppDelegate` is public); tests use `@testable import`.
The module's default isolation is MainActor. Types marked `nonisolated` below are usable from any thread; `@concurrent` functions run off the main actor.

## Feature entry points

| File | Signature |
|---|---|
| `Capture/ScreenCapturer.swift` | `nonisolated enum ScreenCapturer`<br>`@concurrent static func captureDisplays() async throws -> [DisplaySnapshot]`<br>`@concurrent static func captureWindow(_ id: CGWindowID) async throws -> CapturedImage` |
| `Capture/WindowList.swift` | `nonisolated enum WindowList`<br>`static func onScreen() -> [WindowInfo]` (front to back, own pid excluded)<br>`static func hitTest(_ pointCG: CGPoint, in windows: [WindowInfo]) -> WindowInfo?` (pure) |
| `Capture/Selection/SelectionOverlayController.swift` | `final class SelectionOverlayController`<br>`enum Mode { case area, window, adjustableArea }`<br>`func select(mode: Mode, snapshots: [DisplaySnapshot]) async -> Selection?` (nil = cancelled) |
| `Output/ImageEncoder.swift` | `nonisolated enum ImageEncoder`<br>`static func data(_ image: CGImage, scale: CGFloat, format: ImageFormat) throws -> Data` |
| `Output/FileNaming.swift` | `nonisolated enum FileNaming`<br>`static func url(in directory: URL, date: Date, ext: String) -> URL` (must not exist yet) |
| `Output/Clipboard.swift` | `enum Clipboard`<br>`static func copy(image: CGImage, scale: CGFloat, to pasteboard: NSPasteboard = .general)`<br>`static func copy(text: String, to pasteboard: NSPasteboard = .general)` |
| `QuickAccess/QuickAccessController.swift` | `final class QuickAccessController`<br>`enum Item { case image(CapturedImage, URL?), recording(URL) }`<br>`var onAnnotate: ((CapturedImage) -> Void)?`, `var onPin: ((CapturedImage) -> Void)?`<br>`func show(_ item: Item)` |
| `Annotate/Editor/EditorWindowController.swift` | `final class EditorWindowController`<br>`func open(_ capture: CapturedImage)` |
| `Pin/PinWindowController.swift` | `final class PinWindowController`<br>`func pin(_ capture: CapturedImage)` |
| `Record/Recorder.swift` | `@Observable final class Recorder`<br>`private(set) var isRecording: Bool`<br>`var onExternalStop: ((URL) -> Void)?`<br>`func start(_ target: RecordingTarget, options: RecordingOptions) async throws`<br>`func stop() async throws -> URL` |
| `Record/GIFExporter.swift` | `nonisolated enum GIFExporter`<br>`@concurrent static func export(movie: URL, to destination: URL, fps: Int, maxWidth: Int) async throws` |
| `OCR/TextRecognizer.swift` | `nonisolated enum TextRecognizer`<br>`@concurrent static func recognize(_ image: CGImage) async throws -> String` |
| `Hotkeys/HotKeyCenter.swift` | `final class HotKeyCenter`<br>`var handler: ((AppAction) -> Void)?`<br>`@discardableResult func register(_ hotKey: HotKey, action: AppAction) -> Bool` (false = combination taken)<br>`func unregisterAll()` |
| `SettingsUI/SettingsWindowController.swift` | `final class SettingsWindowController`<br>`init(settings: Settings)`<br>`func show()` |

Contracts not visible in the signatures:

- `ScreenCapturer` never includes shotX's own windows. `DisplaySnapshot.image` is native resolution (`frameCG.size * scale`).
- `SelectionOverlayController`: `.area` mode returns `.area(rectPx:snapshot:)` with `rectPx` in that snapshot's pixel space; the snapshot is re-captured when the user lets go (live screen), limited to the display where the drag began; `.window` mode returns `.window(id)`. It calls `WindowList` itself.
- `QuickAccessController`: the image URL is nil when save-after-capture is off. The coordinator sets `onAnnotate` → `EditorWindowController.open`, `onPin` → `PinWindowController.pin`.
- `Recorder` writes an MP4 to a temporary location of its choosing. `stop()` returns it; if recording ends any other way (system UI), it calls `onExternalStop` with it. The coordinator moves/converts the file.
- `HotKeyCenter.handler` is called on the main actor. The coordinator re-registers everything whenever `Settings.hotKeys` changes, so the settings UI only has to mutate settings.
- `Clipboard`'s `to:` parameter exists for tests; production callers omit it.
- The editor and Quick Access may use `Output/*` and `Core/*` directly; they may not call other features.

### Core types (`Core/Models.swift`)

```swift
nonisolated let log: Logger                      // subsystem local.shotx.app
enum ShotXError: LocalizedError                  // notImplemented(String), cropFailed, noDisplay, microphoneDenied, notRecording
enum ImageFormat { png, jpeg }                   // .fileExtension
enum RecordingFormat { mp4, gif }                // .fileExtension
struct DisplaySnapshot { displayID: CGDirectDisplayID; frameCG: CGRect; scale: CGFloat; image: CGImage }
struct CapturedImage   { image: CGImage; scale: CGFloat; displayID: CGDirectDisplayID?; frameCG: CGRect? }
struct WindowInfo      { id: CGWindowID; frameCG: CGRect; ownerPID: pid_t; title: String }
enum Selection         { area(rectPx: CGRect, snapshot: DisplaySnapshot), window(CGWindowID) }
enum RecordingTarget   { display(CGDirectDisplayID), area(rectCG: CGRect, displayID: CGDirectDisplayID) }
struct RecordingOptions { fps: Int; captureMicrophone: Bool; captureSystemAudio: Bool }
struct HotKey          { keyCode: UInt32; modifiers: Modifiers; displayString }   // Modifiers.rawValue == Carbon mask
```

All are `nonisolated` and `Sendable`. `Settings` (`Core/Settings.swift`) is an `@Observable` MainActor class: `saveDirectory`, `imageFormat`, `copyAfterCapture`, `saveAfterCapture`, `showQuickAccess`, `recordingFormat`, `recordingFPS`, `recordMicrophone`, `recordSystemAudio`, `gifFPS`, `gifMaxWidth`, `hotKeys: [AppAction: HotKey]`, `setHotKey(_:for:)`, `debugURLEnabled` (read-only), `static defaultHotKeys`.

Default hotkeys: ⌃⌥A area, ⌃⌥W window, ⌃⌥F fullscreen, ⌃⌥R record area, ⌃⌥⇧R record fullscreen, ⌃⌥S start/stop recording, ⌃⌥T OCR.

## Coordinates

All conversions are in `Core/Geometry.swift` (pure; screen metrics passed in). Suffix every variable and parameter.

| Suffix | Space | Origin, y | Unit | Used by |
|---|---|---|---|---|
| `AppKit` | global | bottom-left of primary display, up | points | `NSScreen.frame`, `NSWindow.frame`, `NSEvent.mouseLocation` |
| `CG` | global | top-left of primary display, down | points | ScreenCaptureKit, `CGWindowList`, `CGEvent.location`, `CGDisplayBounds` |
| `InDisplay` | one display | top-left of that display, down | points | `SCStreamConfiguration.sourceRect` |
| `InView` | a *flipped* view | top-left, down | points | overlay / canvas mouse handling |
| `Px` | a `CGImage` | top-left, down | pixels | cropping, `Selection.area` |

A flipped view that fills a display has `InView == InDisplay`. Views that convert coordinates must override `isFlipped` to true.

| Function | Converts |
|---|---|
| `pointCG(fromAppKit:primaryHeight:)`, `pointAppKit(fromCG:primaryHeight:)` | global point flip |
| `rectCG(fromAppKit:primaryHeight:)`, `rectAppKit(fromCG:primaryHeight:)` | global rect flip |
| `rectInDisplay(fromCG:displayFrameCG:)`, `rectCG(fromInDisplay:displayFrameCG:)` | global ↔ display-local |
| `rectPx(fromInView:scale:imageSizePx:)` | view points → pixels; edges rounded to nearest pixel, clamped to image |
| `rectInView(fromPx:scale:)` | pixels → view points |
| `rectCG(fromPx:displayFrameCG:scale:)` | snapshot pixels → global points |
| `crop(_:toPx:)` | `CGImage` crop, clamped; nil when empty |

`primaryHeight` is `NSScreen.screens[0].frame.height` (the screen with the menu bar, not `NSScreen.main`).

## Flows (`App/AppCoordinator.swift`)

Every flow starts at `perform(_:)`, which ignores a new action while one is in progress, and ends in the single error handler (log + one `NSAlert`).

**captureArea / captureWindow**
1. `Permissions.ensureScreenCapture()` (alert + stop if missing)
2. `ScreenCapturer.captureDisplays()` — display geometry and loupe pixels (the overlay itself shows the live screen)
3. `SelectionOverlayController.select(mode:snapshots:)` — nil → stop
4. `.area` → `Geometry.crop`; `.window` → `ScreenCapturer.captureWindow(id)`
5. Post-capture pipeline

**captureFullscreen:** permission → `captureDisplays()` → snapshot of the display under the mouse → pipeline.

**Post-capture pipeline** (each step per settings): `ImageEncoder.data` → `FileNaming.url` → write file; `Clipboard.copy(image:scale:)`; `QuickAccessController.show(.image(capture, url))`.

**ocr:** steps 1–4 of captureArea → `TextRecognizer.recognize` → `Clipboard.copy(text:)`.

**recordArea:** if recording → stop flow. Else steps 1–3 (`.adjustableArea`: move / resize, then Record or Enter) → `Geometry.rectCG(fromPx:…)` → `Recorder.start(.area(rectCG:displayID:), options:)`.

**recordFullscreen / toggleRecording:** if recording → stop flow. Else permission → `Recorder.start(.display(displayUnderMouse), options:)`. Microphone permission is requested first when `recordMicrophone` is on.

**Stop flow** (also from `Recorder.onExternalStop`): `Recorder.stop()` → temp MP4 → `.mp4`: move to `FileNaming.url`; `.gif`: `GIFExporter.export` then delete the MP4 → `QuickAccessController.show(.recording(url))`.

**openSettings:** `SettingsWindowController.show()`.

**Debug URL:** `shotx://<AppAction rawValue>` → `AppDelegate.application(_:open:)` → `perform`, only when `debugURL` default is true.

## Windows

| Window | Type | Level | Collection behavior | Notes |
|---|---|---|---|---|
| Selection overlay (one per display) | borderless non-activating `NSPanel` | `.screenSaver` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` | see-through over the live screen; flipped content view |
| Quick Access | borderless non-activating `NSPanel` | `.floating` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]` | bottom corner, stacks |
| Pin | borderless `NSPanel` | `.floating` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | aspect-locked resize, opacity |
| Editor | titled `NSWindow` | `.normal` | default | app activates while open |
| Settings | titled `NSWindow` | `.normal` | default | single instance |

shotX is `LSUIElement`; call `NSApp.activate()` before showing a normal-level window. Overlay, Quick Access and Pin windows must not appear in captures (`ScreenCapturer` excludes the app's own windows).
