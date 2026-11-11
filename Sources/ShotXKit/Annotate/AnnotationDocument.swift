import CoreGraphics
import Foundation

/// The editor's model: a base image plus annotations and an optional crop, with undo/redo.
///
/// A value type. That makes two editor patterns free:
/// - **Live drag / in-progress shape:** copy the document, mutate the copy on every mouse move
///   and render the copy; commit to the real document once on mouse-up, so a drag is one undo step.
/// - **Off-main export:** hand a copy to `AnnotationRenderer.export` on another thread.
///
/// Every mutation that changes something pushes one undo snapshot and clears the redo stack;
/// no-op mutations (unknown id, identical value) do neither.
nonisolated struct AnnotationDocument: Sendable {
    let baseImage: CGImage
    /// Pixels per point of the capture (`CapturedImage.scale`).
    let scale: CGFloat
    /// Back to front: later annotations draw on top.
    private(set) var annotations: [Annotation] = []
    /// Applied by `AnnotationRenderer.export` only; nil = whole image. Always inside the image, integral.
    private(set) var cropRectPx: CGRect?

    private struct Snapshot: Sendable {
        var annotations: [Annotation]
        var cropRectPx: CGRect?
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(baseImage: CGImage, scale: CGFloat) {
        self.baseImage = baseImage
        self.scale = scale
    }

    var sizePx: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Number for the next `.counter`: one more than the highest counter present (1 when none).
    var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.kind { number } else { nil }
        }
        return (numbers.max() ?? 0) + 1
    }

    func annotation(id: Annotation.ID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    mutating func add(_ annotation: Annotation) {
        recordUndo()
        annotations.append(annotation)
    }

    /// Replaces the annotation with the same id, keeping its z-position.
    mutating func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }), annotations[index] != annotation else { return }
        recordUndo()
        annotations[index] = annotation
    }

    mutating func remove(id: Annotation.ID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        annotations.remove(at: index)
    }

    /// Sets the export crop, rounded to whole pixels and clamped to the image.
    /// nil, or a rect with no area inside the image, removes the crop.
    mutating func setCrop(_ rectPx: CGRect?) {
        var crop = rectPx.map { $0.standardized.integral.intersection(CGRect(origin: .zero, size: sizePx)) }
        if let rect = crop, rect.isEmpty { crop = nil }  // isEmpty is also true for the null rect
        guard crop != cropRectPx else { return }
        recordUndo()
        cropRectPx = crop
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private var snapshot: Snapshot { Snapshot(annotations: annotations, cropRectPx: cropRectPx) }

    private mutating func recordUndo() {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    private mutating func restore(_ snapshot: Snapshot) {
        annotations = snapshot.annotations
        cropRectPx = snapshot.cropRectPx
    }
}
