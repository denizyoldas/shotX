import CoreGraphics
import Foundation
import os

/// The one logger. Subsystem is the bundle id; filter with `subsystem == "local.shotx.app"`.
nonisolated let log = Logger(subsystem: "local.shotx.app", category: "app")

nonisolated enum ShotXError: LocalizedError {
    case notImplemented(String)
    case cropFailed
    case noDisplay
    case microphoneDenied
    case notRecording

    var errorDescription: String? {
        switch self {
        case .notImplemented(let what): "\(what) is not implemented yet."
        case .cropFailed: "The selected area is outside the captured image."
        case .noDisplay: "No display was captured."
        case .microphoneDenied: "Microphone access is denied. Allow it in System Settings or turn off microphone recording."
        case .notRecording: "No recording is in progress."
        }
    }
}

nonisolated enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

nonisolated enum RecordingFormat: String, Codable, CaseIterable, Sendable {
    case mp4, gif
    var fileExtension: String { rawValue }
}

/// A frozen frame of one whole display.
nonisolated struct DisplaySnapshot: Sendable {
    var displayID: CGDirectDisplayID
    /// Display frame in global CG points (top-left origin of the primary display).
    var frameCG: CGRect
    /// Pixels per point.
    var scale: CGFloat
    /// Full-display image; `width == frameCG.width * scale`.
    var image: CGImage
}

/// A finished capture (cropped area, window or whole display).
nonisolated struct CapturedImage: Sendable {
    var image: CGImage
    /// Pixels per point.
    var scale: CGFloat
    /// Source display, when known.
    var displayID: CGDirectDisplayID?
    /// Where the content was on screen, global CG points, when known.
    var frameCG: CGRect?
}

/// One on-screen window as reported by the window server.
nonisolated struct WindowInfo: Sendable, Equatable {
    var id: CGWindowID
    /// Global CG points.
    var frameCG: CGRect
    var ownerPID: pid_t
    var title: String
}

/// Result of the selection overlay.
nonisolated enum Selection: Sendable {
    /// `rectPx` is in the pixel space of `snapshot.image` (top-left origin).
    case area(rectPx: CGRect, snapshot: DisplaySnapshot)
    case window(CGWindowID)
}

nonisolated enum RecordingTarget: Sendable, Equatable {
    case display(CGDirectDisplayID)
    /// `rectCG` is in global CG points and lies within the given display.
    case area(rectCG: CGRect, displayID: CGDirectDisplayID)
}

nonisolated struct RecordingOptions: Sendable, Equatable {
    var fps: Int
    var captureMicrophone: Bool
    var captureSystemAudio: Bool
}

/// A global keyboard shortcut. `keyCode` is a virtual key code (kVK_*).
nonisolated struct HotKey: Codable, Hashable, Sendable {
    /// Raw values equal Carbon's cmdKey/shiftKey/optionKey/controlKey, so `rawValue` can be
    /// passed straight to RegisterEventHotKey.
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: 1 << 8)
        static let shift = Modifiers(rawValue: 1 << 9)
        static let option = Modifiers(rawValue: 1 << 11)
        static let control = Modifiers(rawValue: 1 << 12)
    }

    var keyCode: UInt32
    var modifiers: Modifiers

    /// e.g. "⌃⌥A".
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key\(keyCode)")
    }

    // ponytail: US ANSI names only; switch to UCKeyTranslate if other layouts must display right.
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
