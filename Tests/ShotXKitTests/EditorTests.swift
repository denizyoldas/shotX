import CoreGraphics
import Testing
@testable import ShotXKit

@Suite struct EditorTests {
    // MARK: CanvasLayout

    @Test func imageThatFitsIsShownAtPointSizeAndCentred() {
        // 400x200 px at 2x = 200x100 pt inside a 300x200 pt canvas.
        let layout = CanvasLayout(imageSizePx: CGSize(width: 400, height: 200), scale: 2, viewSize: CGSize(width: 300, height: 200))
        #expect(layout.zoom == 1)
        #expect(layout.imageRectInView == CGRect(x: 50, y: 50, width: 200, height: 100))
        #expect(layout.pxPerViewPoint == 2)
        #expect(layout.pointPx(fromInView: CGPoint(x: 50, y: 50)) == .zero)
        #expect(layout.pointPx(fromInView: CGPoint(x: 250, y: 150)) == CGPoint(x: 400, y: 200))
        #expect(layout.pointPx(fromInView: CGPoint(x: 40, y: 45)) == CGPoint(x: -20, y: -10))  // letterbox area is outside the image
    }

    @Test func largeImageIsScaledDownAndLetterboxedVertically() {
        // 2000x1000 px at 1x in a 500x500 pt canvas: zoom 0.25, 500x250 pt, 125 pt bars above and below.
        let layout = CanvasLayout(imageSizePx: CGSize(width: 2000, height: 1000), scale: 1, viewSize: CGSize(width: 500, height: 500))
        #expect(layout.zoom == 0.25)
        #expect(layout.imageRectInView == CGRect(x: 0, y: 125, width: 500, height: 250))
        #expect(layout.pxPerViewPoint == 4)
        #expect(layout.pointPx(fromInView: CGPoint(x: 250, y: 250)) == CGPoint(x: 1000, y: 500))
    }

    @Test func retinaImageIsScaledDownAndLetterboxedHorizontally() {
        // 2000x4000 px at 2x = 1000x2000 pt in a 600x500 pt canvas: zoom 0.25, 250x500 pt, 175 pt bars left and right.
        let layout = CanvasLayout(imageSizePx: CGSize(width: 2000, height: 4000), scale: 2, viewSize: CGSize(width: 600, height: 500))
        #expect(layout.zoom == 0.25)
        #expect(layout.imageRectInView == CGRect(x: 175, y: 0, width: 250, height: 500))
        #expect(layout.pxPerViewPoint == 8)
        #expect(layout.pointPx(fromInView: CGPoint(x: 425, y: 500)) == CGPoint(x: 2000, y: 4000))
    }

    @Test func rectInViewIsTheInverseOfPointPx() {
        let layout = CanvasLayout(imageSizePx: CGSize(width: 2000, height: 1000), scale: 1, viewSize: CGSize(width: 500, height: 500))
        let rectInView = layout.rectInView(fromPx: CGRect(x: 400, y: 200, width: 800, height: 400))
        #expect(rectInView == CGRect(x: 100, y: 175, width: 200, height: 100))
        #expect(layout.pointPx(fromInView: rectInView.origin) == CGPoint(x: 400, y: 200))
        #expect(layout.rectInView(fromPx: CGRect(x: 0, y: 0, width: 2000, height: 1000)) == layout.imageRectInView)
    }

    @Test func degenerateSizesDoNotProduceNaN() {
        let layout = CanvasLayout(imageSizePx: CGSize(width: 100, height: 100), scale: 2, viewSize: .zero)
        #expect(layout.zoom > 0)
        #expect(layout.pointPx(fromInView: .zero).x.isFinite)
    }

    // MARK: Tool -> Annotation.Kind

    @Test func dragToolsBuildTheirKindFromStartAndEnd() {
        let a = CGPoint(x: 30, y: 40), b = CGPoint(x: 10, y: 100)
        let rect = CGRect(x: 30, y: 40, width: -20, height: 60)  // un-normalised on purpose
        #expect(EditorTool.arrow.kind(fromPx: a, toPx: b) == .arrow(fromPx: a, toPx: b))
        #expect(EditorTool.line.kind(fromPx: a, toPx: b) == .line(fromPx: a, toPx: b))
        #expect(EditorTool.rectangle.kind(fromPx: a, toPx: b) == .rectangle(rect))
        #expect(EditorTool.ellipse.kind(fromPx: a, toPx: b) == .ellipse(rect))
        #expect(EditorTool.highlight.kind(fromPx: a, toPx: b) == .highlight(rect))
        #expect(EditorTool.blur.kind(fromPx: a, toPx: b) == .blur(rect))
        #expect(EditorTool.pixelate.kind(fromPx: a, toPx: b) == .pixelate(rect))
    }

    @Test func otherToolsAreNotTwoPointDrags() {
        for tool in [EditorTool.select, .freehand, .text, .counter, .crop] {
            #expect(tool.kind(fromPx: .zero, toPx: CGPoint(x: 10, y: 10)) == nil)
        }
    }

    @Test func everyToolHasADistinctSymbolAndTitle() {
        #expect(Set(EditorTool.allCases.map(\.symbol)).count == EditorTool.allCases.count)
        #expect(Set(EditorTool.allCases.map(\.title)).count == EditorTool.allCases.count)
    }
}
