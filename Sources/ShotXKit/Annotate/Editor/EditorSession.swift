import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// One open editor: its window, the document and tool state the toolbar and canvas share,
/// and the copy / save actions.
@Observable
final class EditorSession: NSObject, NSWindowDelegate {
    /// Line width and font size in points; multiplied by the document scale so 1x and 2x captures look alike.
    struct StylePreset {
        var name: String
        var lineWidth: CGFloat
        var fontSize: CGFloat
    }

    static let palette: [(name: String, color: CGColor)] = [
        ("Red", Annotation.Style.standard(scale: 1).color),
        ("Orange", CGColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1)),
        ("Yellow", CGColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)),
        ("Green", CGColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)),
        ("Blue", CGColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)),
        ("Purple", CGColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1)),
        ("Black", CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
        ("White", CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)),
    ]
    /// "Medium" equals `Annotation.Style.standard`.
    static let presets = [
        StylePreset(name: "Thin", lineWidth: 2, fontSize: 12),
        StylePreset(name: "Medium", lineWidth: 3, fontSize: 16),
        StylePreset(name: "Thick", lineWidth: 6, fontSize: 24),
    ]
    private static let minCanvasHeight: CGFloat = 160

    var document: AnnotationDocument
    private(set) var tool = EditorTool.arrow
    /// Style for new annotations.
    private(set) var style: Annotation.Style
    var selectedID: Annotation.ID?

    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private let window: NSWindow

    init(capture: CapturedImage) {
        document = AnnotationDocument(baseImage: capture.image, scale: capture.scale)
        style = .standard(scale: capture.scale)
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
    }

    func show() {
        let toolbar = NSHostingView(rootView: EditorToolbar(session: self))
        let canvas = CanvasView(session: self)
        let content = NSView()
        for view in [toolbar, canvas] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minCanvasHeight),
        ])
        window.contentView = content

        // Zoom to fit: image at point size, shrunk until the window is at most ~80% of the screen.
        let toolbarSize = toolbar.fittingSize
        let screenSize = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let maxCanvasSize = CGSize(width: screenSize.width * 0.8, height: screenSize.height * 0.8 - toolbarSize.height)
        let fitted = CanvasLayout(imageSizePx: document.sizePx, scale: document.scale, viewSize: maxCanvasSize).imageRectInView.size
        window.setContentSize(CGSize(width: max(fitted.width, toolbarSize.width),
                                     height: max(fitted.height, Self.minCanvasHeight) + toolbarSize.height))
        window.title = "shotX — Annotate"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    // MARK: State changes (each document mutation is one undo step)

    func choose(_ tool: EditorTool) {
        self.tool = tool
        if tool != .select { selectedID = nil }
    }

    func apply(color: CGColor) {
        restyle { $0.color = color }
    }

    func apply(_ preset: StylePreset) {
        let scale = document.scale
        restyle {
            $0.lineWidthPx = preset.lineWidth * scale
            $0.fontSizePx = preset.fontSize * scale
        }
    }

    /// Changes the style for new annotations and, when one is selected, that annotation.
    private func restyle(_ change: (inout Annotation.Style) -> Void) {
        change(&style)
        guard let id = selectedID, var annotation = document.annotation(id: id) else { return }
        change(&annotation.style)
        document.update(annotation)
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        selectedID = nil
        document.remove(id: id)
    }

    // MARK: Output

    func copy(thenClose: Bool = false) {
        commitTextEntry()
        let document = document
        Task {
            do {
                Clipboard.copy(image: try await Self.export(document), scale: document.scale)
                if thenClose { window.close() }
            } catch {
                present(error)
            }
        }
    }

    func save() {
        commitTextEntry()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.showsContentTypes = true
        // The panel picks the folder; FileNaming only supplies the name pattern here.
        panel.nameFieldStringValue = FileNaming.url(in: FileManager.default.temporaryDirectory, date: Date(),
                                                    ext: ImageFormat.png.fileExtension).lastPathComponent
        Task {
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
            do {
                try await Self.write(document, to: url)
            } catch {
                present(error)
            }
        }
    }

    func close() {
        window.performClose(nil)
    }

    /// Toolbar buttons do not take first responder, so text still being typed would be left out of the
    /// output. Resigning the field ends editing synchronously, which adds the text to the document.
    private func commitTextEntry() {
        window.makeFirstResponder(nil)
    }

    private func present(_ error: Error) {
        log.error("editor: \(error.localizedDescription, privacy: .public)")
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private nonisolated static func render(_ document: AnnotationDocument) throws -> CGImage {
        guard let image = AnnotationRenderer.export(document) else { throw ImageEncoder.EncodingFailed(type: .png) }
        return image
    }

    @concurrent private nonisolated static func export(_ document: AnnotationDocument) async throws -> CGImage {
        try render(document)
    }

    @concurrent private nonisolated static func write(_ document: AnnotationDocument, to url: URL) async throws {
        let isJPEG = UTType(filenameExtension: url.pathExtension)?.conforms(to: .jpeg) == true
        try ImageEncoder.data(try render(document), scale: document.scale, format: isJPEG ? .jpeg : .png).write(to: url, options: .atomic)
    }

    // MARK: NSWindowDelegate

    // ponytail: closing discards unsaved annotations without asking (the original capture is
    // already on the clipboard / disk). Add windowShouldClose + a confirm sheet if that bites.
    func windowWillClose(_ notification: Notification) {
        // After the close has finished: break the session -> window -> views -> session cycle
        // and let the controller drop us. Doing it inside the callback would tear down a window
        // that AppKit is still closing.
        Task {
            window.contentView = nil
            onClose?()
        }
    }
}
