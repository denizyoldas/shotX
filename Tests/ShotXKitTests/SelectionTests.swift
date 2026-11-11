import CoreGraphics
import Testing
@testable import ShotXKit

struct SelectionTests {
    let boundsInView = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func dragIsNormalisedInEveryDirection() {
        let expectedInView = CGRect(x: 100, y: 200, width: 300, height: 400)
        let cornersInView = [CGPoint(x: 100, y: 200), CGPoint(x: 400, y: 200), CGPoint(x: 100, y: 600), CGPoint(x: 400, y: 600)]
        for (startInView, endInView) in zip(cornersInView, cornersInView.reversed()) {
            #expect(SelectionMath.dragRectInView(from: startInView, to: endInView, boundsInView: boundsInView) == expectedInView)
        }
    }

    @Test func dragIsClampedToTheView() {
        let rectInView = SelectionMath.dragRectInView(
            from: CGPoint(x: 900, y: 700), to: CGPoint(x: 1500, y: -50), boundsInView: boundsInView
        )
        #expect(rectInView == CGRect(x: 900, y: 0, width: 100, height: 700))
    }

    @Test func dragUnderThreePointsCancels() {
        let startInView = CGPoint(x: 10, y: 10)
        #expect(!SelectionMath.isDrag(from: startInView, to: CGPoint(x: 12, y: 12)))
        #expect(SelectionMath.isDrag(from: startInView, to: CGPoint(x: 13, y: 10)))
        #expect(SelectionMath.areaRectPx(
            from: startInView, to: CGPoint(x: 12, y: 11), boundsInView: boundsInView, scale: 2,
            imageSizePx: CGSize(width: 2000, height: 1600)
        ) == nil)
    }

    @Test func dragWithNoAreaCancels() {
        // Long enough, but dragged along the edge outside the view: zero height after clamping.
        #expect(SelectionMath.areaRectPx(
            from: CGPoint(x: 10, y: 800), to: CGPoint(x: 500, y: 900), boundsInView: boundsInView, scale: 1,
            imageSizePx: CGSize(width: 1000, height: 800)
        ) == nil)
    }

    @Test(arguments: [(CGFloat(1), CGRect(x: 100, y: 200, width: 300, height: 400), "300 × 400"),
                      (CGFloat(2), CGRect(x: 200, y: 400, width: 600, height: 800), "600 × 800")])
    func areaRectAndLabelFollowScale(scale: CGFloat, expectedPx: CGRect, label: String) {
        let rectPx = SelectionMath.areaRectPx(
            from: CGPoint(x: 400, y: 600), to: CGPoint(x: 100, y: 200), boundsInView: boundsInView, scale: scale,
            imageSizePx: CGSize(width: 1000 * scale, height: 800 * scale)
        )
        #expect(rectPx == expectedPx)
        #expect(rectPx.map(SelectionMath.sizeLabel(rectPx:)) == label)
    }

    @Test func fractionalDragRoundsToWholePixelsAt2x() {
        let rectPx = SelectionMath.areaRectPx(
            from: CGPoint(x: 10.25, y: 10.25), to: CGPoint(x: 20.75, y: 30.3), boundsInView: boundsInView, scale: 2,
            imageSizePx: CGSize(width: 2000, height: 1600)
        )
        #expect(rectPx == CGRect(x: 21, y: 21, width: 21, height: 40))
    }

    @Test func loupeIsCentredOnThePixelUnderTheCursor() {
        let sizePx = CGSize(width: 2000, height: 1600)
        let at1x = SelectionMath.loupeSourceRectPx(cursorInView: CGPoint(x: 100.6, y: 50.2), scale: 1, imageSizePx: sizePx)
        #expect(at1x == CGRect(x: 93, y: 43, width: 15, height: 15))
        let at2x = SelectionMath.loupeSourceRectPx(cursorInView: CGPoint(x: 100.6, y: 50.2), scale: 2, imageSizePx: sizePx)
        #expect(at2x == CGRect(x: 194, y: 93, width: 15, height: 15))
        // At the far corner the centre stays on the last pixel and the rect overhangs the image.
        let cornerPx = SelectionMath.loupeSourceRectPx(cursorInView: CGPoint(x: 1000, y: 800), scale: 2, imageSizePx: sizePx)
        #expect(cornerPx == CGRect(x: 1992, y: 1592, width: 15, height: 15))
    }

    @Test func loupeFlipsAwayFromTheEdges() {
        func originInView(_ cursorInView: CGPoint) -> CGPoint {
            SelectionMath.loupeOriginInView(cursorInView: cursorInView, side: 120, offset: 20, boundsInView: boundsInView)
        }
        #expect(originInView(CGPoint(x: 100, y: 100)) == CGPoint(x: 120, y: 120))
        #expect(originInView(CGPoint(x: 950, y: 100)) == CGPoint(x: 810, y: 120))
        #expect(originInView(CGPoint(x: 950, y: 750)) == CGPoint(x: 810, y: 610))
    }

    @Test func movedRectKeepsItsSizeAndStaysInside() {
        let rectInView = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(SelectionMath.moved(rectInView, by: CGSize(width: 50, height: -20), boundsInView: boundsInView)
            == CGRect(x: 150, y: 80, width: 200, height: 100))
        #expect(SelectionMath.moved(rectInView, by: CGSize(width: 5000, height: -5000), boundsInView: boundsInView)
            == CGRect(x: 800, y: 0, width: 200, height: 100))
    }

    @Test func grabbingACornerFixesTheOppositeOne() {
        let rectInView = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(SelectionMath.fixedCorner(of: rectInView, grabbedAt: CGPoint(x: 104, y: 97), tolerance: 8)
            == CGPoint(x: 300, y: 200))
        #expect(SelectionMath.fixedCorner(of: rectInView, grabbedAt: CGPoint(x: 300, y: 200), tolerance: 8)
            == CGPoint(x: 100, y: 100))
        #expect(SelectionMath.fixedCorner(of: rectInView, grabbedAt: CGPoint(x: 200, y: 150), tolerance: 8) == nil)
    }
}
