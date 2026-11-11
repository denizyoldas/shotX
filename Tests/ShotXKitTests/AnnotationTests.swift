import CoreGraphics
import Foundation
import Testing
@testable import ShotXKit

/// RGBA8 sRGB copy of an image; `self[x, y]` uses top-left pixel coordinates.
private struct Bitmap {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    subscript(x: Int, y: Int) -> [Int] {
        let i = (y * width + x) * 4
        return bytes[i..<i + 4].map(Int.init)
    }
}

private func close(_ pixel: [Int], _ expected: [Int], tolerance: Int = 8) -> Bool {
    zip(pixel, expected).allSatisfy { abs($0 - $1) <= tolerance }
}

private let white = [255, 255, 255, 255]
private let red = [255, 0, 0, 255]
private let style = Annotation.Style(color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), lineWidthPx: 4, fontSizePx: 40)

/// 200×200 sRGB test image: plain white, or 4 px black/white vertical stripes.
private func testImage(striped: Bool = false) throws -> CGImage {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    if striped {
        context.setFillColor(gray: 0, alpha: 1)
        for x in stride(from: 0, to: 200, by: 8) { context.fill(CGRect(x: x, y: 0, width: 4, height: 200)) }
    }
    return try #require(context.makeImage())
}

private func rendered(_ kinds: Annotation.Kind..., striped: Bool = false) throws -> Bitmap {
    var document = AnnotationDocument(baseImage: try testImage(striped: striped), scale: 1)
    for kind in kinds { document.add(Annotation(kind: kind, style: style)) }
    return try Bitmap(try #require(AnnotationRenderer.export(document)))
}

struct AnnotationRenderTests {
    @Test func arrowHasShaftAndWiderHead() throws {
        let bitmap = try rendered(.arrow(fromPx: CGPoint(x: 20, y: 100), toPx: CGPoint(x: 120, y: 100)))
        #expect(close(bitmap[60, 100], red))      // shaft
        #expect(close(bitmap[60, 105], white))    // just outside the 4 px shaft
        #expect(close(bitmap[108, 103], red))     // head is wider than the shaft
        #expect(close(bitmap[90, 103], white))    // same row, behind the head: shaft only
        #expect(close(bitmap[116, 100], red))     // near the tip
        #expect(close(bitmap[126, 100], white))   // past the tip
        #expect(close(bitmap[180, 180], white))
    }

    @Test func rectangleStrokesOutlineOnly() throws {
        let bitmap = try rendered(.rectangle(CGRect(x: 20, y: 20, width: 100, height: 60)))
        #expect(close(bitmap[20, 50], red))
        #expect(close(bitmap[70, 20], red))
        #expect(close(bitmap[119, 79], red))
        #expect(close(bitmap[70, 50], white))
        #expect(close(bitmap[180, 180], white))
    }

    @Test func unnormalisedRectDrawsLikeNormalised() throws {
        let a = try rendered(.rectangle(CGRect(x: 120, y: 80, width: -100, height: -60)))
        let b = try rendered(.rectangle(CGRect(x: 20, y: 20, width: 100, height: 60)))
        #expect(a.bytes == b.bytes)
    }

    @Test func ellipseStrokesOutlineOnly() throws {
        let bitmap = try rendered(.ellipse(CGRect(x: 20, y: 20, width: 100, height: 60)))
        #expect(close(bitmap[20, 50], red))
        #expect(close(bitmap[70, 20], red))
        #expect(close(bitmap[70, 50], white))
        #expect(close(bitmap[22, 22], white))     // corner of the bounding box is outside the ellipse
        #expect(close(bitmap[180, 180], white))
    }

    @Test func lineAndFreehand() throws {
        let bitmap = try rendered(
            .line(fromPx: CGPoint(x: 10, y: 10), toPx: CGPoint(x: 110, y: 10)),
            .freehand(pointsPx: [CGPoint(x: 10, y: 150), CGPoint(x: 60, y: 150), CGPoint(x: 60, y: 190)]))
        #expect(close(bitmap[60, 10], red))
        #expect(close(bitmap[30, 150], red))
        #expect(close(bitmap[60, 170], red))
        #expect(close(bitmap[30, 170], white))
        #expect(close(bitmap[180, 100], white))
    }

    @Test func highlightIsSemiTransparent() throws {
        let bitmap = try rendered(.highlight(CGRect(x: 40, y: 40, width: 60, height: 30)))
        #expect(close(bitmap[70, 55], [255, 153, 153, 255]))  // 40 % red over white
        #expect(close(bitmap[70, 80], white))
    }

    @Test func textDrawsOnlyInsideItsBounds() throws {
        let annotation = Annotation(kind: .text("Hi\nyou", originPx: CGPoint(x: 20, y: 30)), style: style)
        var document = AnnotationDocument(baseImage: try testImage(), scale: 1)
        document.add(annotation)
        let bitmap = try Bitmap(try #require(AnnotationRenderer.export(document)))
        let bounds = annotation.boundsPx.insetBy(dx: -2, dy: -2)
        var inked = 0, inkedLowerHalf = 0
        for y in 0..<200 {
            for x in 0..<200 where !close(bitmap[x, y], white) {
                #expect(bounds.contains(CGPoint(x: x, y: y)), "ink outside bounds at \(x),\(y)")
                inked += 1
                if CGFloat(y) > annotation.boundsPx.midY { inkedLowerHalf += 1 }
            }
        }
        #expect(inked > 100)
        #expect(inkedLowerHalf > 50)  // second line is below the first, not on top of it
        #expect(annotation.boundsPx.minY == 30)
    }

    @Test func textIsUpright() throws {
        // "L" has its horizontal bar at the bottom; a vertically mirrored one would have it on top.
        let annotation = Annotation(kind: .text("L", originPx: CGPoint(x: 20, y: 20)), style: style)
        var document = AnnotationDocument(baseImage: try testImage(), scale: 1)
        document.add(annotation)
        let bitmap = try Bitmap(try #require(AnnotationRenderer.export(document)))
        var rows: [Int: Int] = [:]
        for y in 0..<200 { for x in 0..<200 where !close(bitmap[x, y], white, tolerance: 100) { rows[y, default: 0] += 1 } }
        let top = try #require(rows.keys.min()), bottom = try #require(rows.keys.max())
        #expect(try #require(rows[bottom - 1]) > 2 * (try #require(rows[top + 1])))
    }

    @Test func counterIsFilledBadgeWithNumber() throws {
        let bitmap = try rendered(.counter(centerPx: CGPoint(x: 100, y: 100), number: 7))
        #expect(close(bitmap[100 - 33, 100], red))    // radius is 36
        #expect(close(bitmap[100, 100 + 33], red))
        #expect(close(bitmap[100 - 40, 100], white))
        var whiteInside = 0
        for y in 85..<115 { for x in 85..<115 where close(bitmap[x, y], white, tolerance: 40) { whiteInside += 1 } }
        #expect(whiteInside > 20)                     // the digit
        #expect(close(bitmap[180, 180], white))
    }

    @Test func cropExportHasCropSizeAndOffset() throws {
        var document = AnnotationDocument(baseImage: try testImage(), scale: 1)
        document.add(Annotation(kind: .line(fromPx: CGPoint(x: 0, y: 60), toPx: CGPoint(x: 200, y: 60)), style: style))
        document.setCrop(CGRect(x: 50, y: 50, width: 80, height: 40))
        let image = try #require(AnnotationRenderer.export(document))
        #expect(image.width == 80)
        #expect(image.height == 40)
        let bitmap = try Bitmap(image)
        #expect(close(bitmap[10, 10], red))   // y 60 in the image is y 10 in the crop
        #expect(close(bitmap[10, 30], white))
    }

    @Test(arguments: [true, false]) func effectChangesOnlyItsRect(blur: Bool) throws {
        let rect = CGRect(x: 40, y: 40, width: 60, height: 60)
        let base = try Bitmap(try testImage(striped: true))
        let bitmap = try rendered(blur ? .blur(rect) : .pixelate(rect), striped: true)
        var changedInside = 0
        for y in 0..<200 {
            for x in 0..<200 {
                if rect.contains(CGPoint(x: x, y: y)) {
                    if !close(bitmap[x, y], base[x, y], tolerance: 40) { changedInside += 1 }
                } else {
                    #expect(bitmap[x, y] == base[x, y], "pixel outside the rect changed at \(x),\(y)")
                }
            }
        }
        // Blur turns the stripes grey everywhere; CIPixellate samples rather than averages, so its
        // 12 px blocks come out black or white and only the pixels that disagree with their block change.
        #expect(changedInside > (blur ? 3000 : 1500), "\(changedInside) of 3600 changed")
        if blur { #expect(close(bitmap[70, 70], [128, 128, 128, 255], tolerance: 70)) }
    }
}

struct AnnotationDocumentTests {
    private func counter(_ number: Int) -> Annotation {
        Annotation(kind: .counter(centerPx: CGPoint(x: 10, y: 10), number: number), style: style)
    }

    @Test func undoRedoSequence() throws {
        var document = AnnotationDocument(baseImage: try testImage(), scale: 2)
        #expect(!document.canUndo && !document.canRedo)
        let a = counter(1), b = counter(2), c = counter(3)
        document.add(a)
        document.add(b)
        document.update(b.moved(by: CGVector(dx: 5, dy: 0)))
        document.setCrop(CGRect(x: 0, y: 0, width: 50, height: 50))
        document.remove(id: a.id)
        #expect(document.annotations.map(\.id) == [b.id])

        document.undo()  // remove
        #expect(document.annotations.map(\.id) == [a.id, b.id])
        document.undo()  // crop
        #expect(document.cropRectPx == nil)
        document.undo()  // move
        #expect(document.annotation(id: b.id) == b)
        document.redo()
        #expect(document.annotation(id: b.id) == b.moved(by: CGVector(dx: 5, dy: 0)))
        document.redo()
        #expect(document.cropRectPx == CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(document.canRedo)

        document.undo()
        document.add(c)  // a new edit clears the redo stack
        #expect(!document.canRedo)
        document.redo()
        #expect(document.annotations.map(\.id) == [a.id, b.id, c.id])
        #expect(document.cropRectPx == nil)

        for _ in 0..<10 { document.undo() }
        #expect(document.annotations.isEmpty && !document.canUndo)
    }

    @Test func noOpMutationsLeaveUndoStackAlone() throws {
        var document = AnnotationDocument(baseImage: try testImage(), scale: 1)
        let a = counter(1)
        document.update(a)
        document.remove(id: a.id)
        document.setCrop(nil)
        document.setCrop(CGRect(x: 500, y: 500, width: 10, height: 10))  // entirely outside
        #expect(!document.canUndo)
        document.add(a)
        document.update(a)
        document.undo()
        #expect(document.annotations.isEmpty)
    }

    @Test func cropIsClampedAndIntegral() throws {
        var document = AnnotationDocument(baseImage: try testImage(), scale: 1)
        document.setCrop(CGRect(x: 150.4, y: -20, width: 100, height: 60.2))
        #expect(document.cropRectPx == CGRect(x: 150, y: 0, width: 50, height: 41))
    }

    @Test func counterNumbering() throws {
        var document = AnnotationDocument(baseImage: try testImage(), scale: 1)
        #expect(document.nextCounterNumber == 1)
        document.add(counter(document.nextCounterNumber))
        document.add(Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 5, height: 5)), style: style))
        let second = counter(document.nextCounterNumber)
        document.add(second)
        #expect(document.nextCounterNumber == 3)
        document.remove(id: second.id)
        #expect(document.nextCounterNumber == 2)
        document.undo()
        #expect(document.nextCounterNumber == 3)
    }
}

struct AnnotationGeometryTests {
    private func make(_ kind: Annotation.Kind) -> Annotation { Annotation(kind: kind, style: style) }

    @Test func hitTestStrokedShapes() {
        let line = make(.line(fromPx: CGPoint(x: 0, y: 0), toPx: CGPoint(x: 100, y: 100)))
        #expect(line.hitTest(CGPoint(x: 50, y: 53)))
        #expect(!line.hitTest(CGPoint(x: 50, y: 70)))
        #expect(line.hitTest(CGPoint(x: 50, y: 70), tolerancePx: 20))
        #expect(!line.hitTest(CGPoint(x: 120, y: 120)))  // beyond the end point

        let rectangle = make(.rectangle(CGRect(x: 120, y: 80, width: -100, height: -60)))
        #expect(rectangle.hitTest(CGPoint(x: 22, y: 50)))
        #expect(!rectangle.hitTest(CGPoint(x: 70, y: 50)))  // inside, away from the outline
        #expect(!rectangle.hitTest(CGPoint(x: 140, y: 50)))

        let ellipse = make(.ellipse(CGRect(x: 20, y: 20, width: 100, height: 60)))
        #expect(ellipse.hitTest(CGPoint(x: 70, y: 21)))
        #expect(!ellipse.hitTest(CGPoint(x: 70, y: 50)))
        #expect(!ellipse.hitTest(CGPoint(x: 21, y: 21)))  // bounding-box corner

        let freehand = make(.freehand(pointsPx: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)]))
        #expect(freehand.hitTest(CGPoint(x: 52, y: 30)))
        #expect(!freehand.hitTest(CGPoint(x: 20, y: 30)))
        #expect(!make(.freehand(pointsPx: [])).hitTest(.zero))
    }

    @Test func hitTestFilledShapes() {
        for kind in [Annotation.Kind.highlight, Annotation.Kind.blur, Annotation.Kind.pixelate] {
            let annotation = make(kind(CGRect(x: 10, y: 10, width: 40, height: 40)))
            #expect(annotation.hitTest(CGPoint(x: 30, y: 30)))
            #expect(annotation.hitTest(CGPoint(x: 52, y: 30)))
            #expect(!annotation.hitTest(CGPoint(x: 60, y: 30)))
        }
        let counter = make(.counter(centerPx: CGPoint(x: 100, y: 100), number: 1))
        #expect(counter.hitTest(CGPoint(x: 120, y: 100)))
        #expect(!counter.hitTest(CGPoint(x: 150, y: 100)))
        let text = make(.text("Hello", originPx: CGPoint(x: 10, y: 10)))
        #expect(text.hitTest(CGPoint(x: 20, y: 30)))
        #expect(!text.hitTest(CGPoint(x: 20, y: 100)))
    }

    @Test func boundsIncludeStrokeAndHead() {
        #expect(make(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))).boundsPx == CGRect(x: 8, y: 8, width: 24, height: 24))
        #expect(make(.arrow(fromPx: CGPoint(x: 10, y: 50), toPx: CGPoint(x: 60, y: 50))).boundsPx == CGRect(x: 3, y: 43, width: 64, height: 14))
        #expect(make(.counter(centerPx: CGPoint(x: 100, y: 100), number: 1)).boundsPx == CGRect(x: 64, y: 64, width: 72, height: 72))
    }

    @Test func movedTranslatesEveryKind() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let a = CGPoint(x: 1, y: 2), b = CGPoint(x: 30, y: 40)
        let kinds: [Annotation.Kind] = [
            .arrow(fromPx: a, toPx: b), .line(fromPx: a, toPx: b), .freehand(pointsPx: [a, b]), .rectangle(rect), .ellipse(rect),
            .highlight(rect), .blur(rect), .pixelate(rect), .text("x", originPx: a), .counter(centerPx: b, number: 4),
        ]
        let delta = CGVector(dx: 7, dy: -3)
        for kind in kinds {
            let original = make(kind)
            let moved = original.moved(by: delta)
            #expect(moved.id == original.id)
            #expect(moved.style == original.style)
            let expected = original.boundsPx.offsetBy(dx: 7, dy: -3)
            #expect(abs(moved.boundsPx.minX - expected.minX) < 0.001 && abs(moved.boundsPx.minY - expected.minY) < 0.001, "\(kind)")
            #expect(abs(moved.boundsPx.width - expected.width) < 0.001 && abs(moved.boundsPx.height - expected.height) < 0.001, "\(kind)")
            #expect(moved.moved(by: CGVector(dx: -7, dy: 3)) == original)
        }
        if case .counter(_, let number) = make(.counter(centerPx: b, number: 4)).moved(by: delta).kind { #expect(number == 4) }
    }
}
