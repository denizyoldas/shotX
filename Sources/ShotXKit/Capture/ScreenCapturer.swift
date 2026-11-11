import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Still images via ScreenCaptureKit. Never includes shotX's own windows.
nonisolated enum ScreenCapturer {
    enum CaptureError: LocalizedError {
        case windowGone
        var errorDescription: String? { "The window is no longer on screen." }
    }

    /// One snapshot per connected display, at native pixel resolution, captured concurrently.
    @concurrent static func captureDisplays() async throws -> [DisplaySnapshot] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displayIDs, &count)
        let ids = displayIDs.prefix(Int(count))

        let snapshots = try await withThrowingTaskGroup(of: (Int, DisplaySnapshot?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await captureDisplay(id)) }
            }
            var results: [(Int, DisplaySnapshot?)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.compactMap(\.1)  // active-list order: primary first
        }
        guard !snapshots.isEmpty else { throw ShotXError.noDisplay }
        return snapshots
    }

    /// nil when ScreenCaptureKit does not offer the display (e.g. a mirror of another one).
    // ponytail: one SCShareableContent query per display, because SCK objects are not Sendable and cannot
    // cross into the child tasks; the queries run concurrently so wall time is unaffected. Share one query
    // if SCContentFilter ever becomes Sendable.
    private static func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> DisplaySnapshot? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration(for: filter))
        return DisplaySnapshot(
            displayID: displayID, frameCG: CGDisplayBounds(displayID), scale: CGFloat(filter.pointPixelScale), image: image)
    }

    /// Live capture of one window on a transparent background, shadow included.
    /// `frameCG` is the window frame; the image is larger than `frameCG.size * scale` by the shadow margin.
    @concurrent static func captureWindow(_ id: CGWindowID) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowGone }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = configuration(for: filter)
        config.ignoreShadowsSingleWindow = false
        config.ignoreGlobalClipSingleWindow = true  // a window hanging off the screen edge is still captured whole
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let frameCG = window.frame
        let displayID = content.displays.first { $0.frame.intersects(frameCG) }?.displayID
        return CapturedImage(image: image, scale: CGFloat(filter.pointPixelScale), displayID: displayID, frameCG: frameCG)
    }

    /// Native pixel size of the filter's content, no cursor. Background stays the default (clear).
    private static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return config
    }
}
