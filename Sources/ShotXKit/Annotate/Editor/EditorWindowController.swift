/// Opens annotation editors. Each `open` gets its own window; the session is kept alive here
/// until its window closes.
final class EditorWindowController {
    private var sessions: [EditorSession] = []

    func open(_ capture: CapturedImage) {
        let session = EditorSession(capture: capture)
        session.onClose = { [weak self, weak session] in
            self?.sessions.removeAll { $0 === session }
            AnnotationRenderer.clearCache()
        }
        sessions.append(session)
        session.show()
    }
}
