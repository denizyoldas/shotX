/// Everything the user can trigger. Menu, hotkeys and the debug URL all funnel through
/// `AppCoordinator.perform(_:)`. The raw value is the debug URL host: `shotx://captureArea`.
nonisolated enum AppAction: String, CaseIterable, Codable, Sendable {
    case captureArea, captureWindow, captureFullscreen
    case recordArea, recordFullscreen, toggleRecording
    case ocr, openSettings

    var title: String {
        switch self {
        case .captureArea: "Capture Area"
        case .captureWindow: "Capture Window"
        case .captureFullscreen: "Capture Fullscreen"
        case .recordArea: "Record Area"
        case .recordFullscreen: "Record Fullscreen"
        case .toggleRecording: "Start/Stop Recording"
        case .ocr: "Capture Text (OCR)"
        case .openSettings: "Settings…"
        }
    }
}
