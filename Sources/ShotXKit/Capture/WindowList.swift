import CoreGraphics
import Foundation

/// Window-server window list for hit-testing in the selection overlay.
nonisolated enum WindowList {
    /// Smaller windows are helper/overlay slivers nobody wants to screenshot.
    static let minimumSide: CGFloat = 40

    /// On-screen windows, front to back, excluding this process's own.
    static func onScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return parse(entries, excludingPID: getpid())
    }

    /// Frontmost window containing the point. `windows` must be front to back. Pure.
    static func hitTest(_ pointCG: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frameCG.contains(pointCG) }
    }

    /// Keeps normal (layer 0), visible, reasonably sized windows not owned by `excludingPID`; order preserved. Pure.
    static func parse(_ entries: [[String: Any]], excludingPID: pid_t) -> [WindowInfo] {
        entries.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != excludingPID,
                  let layer = entry[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frameCG = CGRect(dictionaryRepresentation: bounds),
                  frameCG.width >= minimumSide, frameCG.height >= minimumSide,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01
            else { return nil }
            // kCGWindowName is absent without Screen Recording permission; the app name is the fallback.
            let name = entry[kCGWindowName as String] as? String ?? ""
            let title = name.isEmpty ? entry[kCGWindowOwnerName as String] as? String ?? "" : name
            return WindowInfo(id: number.uint32Value, frameCG: frameCG, ownerPID: pid.int32Value, title: title)
        }
    }
}
