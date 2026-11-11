import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var coordinator: AppCoordinator?
    private var statusItem: StatusItemController?

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(settings: settings)
        self.coordinator = coordinator
        statusItem = StatusItemController(coordinator: coordinator, settings: settings)
        log.info("shotX launched")
    }

    /// Quitting mid-recording would leave an unfinalized, unplayable movie: save it first.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.isRecording else { return .terminateNow }
        Task {
            await coordinator.finishRecording()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.releaseSystemShortcuts()
    }

    /// Debug URL scheme: `shotx://<AppAction>` and the smoke-only `shotx://capture-area?x=&y=&w=&h=`
    /// (global CG points). Off unless the `debugURL` default is true.
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard settings.debugURLEnabled else {
            log.info("URL ignored: debugURL is off")
            return
        }
        for url in urls where url.scheme == "shotx" {
            let host = url.host()?.lowercased()
            if host == "capture-area" {
                if let rectCG = Self.captureAreaRectCG(from: url) {
                    coordinator?.debugCaptureArea(rectCG: rectCG)
                } else {
                    log.error("capture-area needs finite x, y and positive w, h: \(url.absoluteString, privacy: .public)")
                }
            } else if let action = AppAction.allCases.first(where: { $0.rawValue.lowercased() == host }) {
                coordinator?.perform(action)
            } else {
                log.error("URL names no AppAction: \(url.absoluteString, privacy: .public)")
            }
        }
    }

    /// Nil unless x, y, w, h are all present and finite and w, h are positive. Whether the rect lies
    /// on a display is checked by the coordinator against the captured displays.
    static func captureAreaRectCG(from url: URL) -> CGRect? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func number(_ name: String) -> Double? {
            items.first { $0.name == name }?.value.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        }
        guard let x = number("x"), let y = number("y"), let w = number("w"), let h = number("h"), w > 0, h > 0 else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
