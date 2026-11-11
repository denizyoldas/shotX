import CoreGraphics
import Testing
@testable import ShotXKit

struct GeometryTests {
    let primaryHeight: CGFloat = 1080

    @Test func flipsRectOnPrimary() {
        let rectAppKit = CGRect(x: 100, y: 200, width: 300, height: 400)
        let rectCG = Geometry.rectCG(fromAppKit: rectAppKit, primaryHeight: primaryHeight)
        #expect(rectCG == CGRect(x: 100, y: 480, width: 300, height: 400))
        #expect(Geometry.rectAppKit(fromCG: rectCG, primaryHeight: primaryHeight) == rectAppKit)
    }

    @Test func flipsPoint() {
        let pointCG = Geometry.pointCG(fromAppKit: CGPoint(x: -50, y: 1100), primaryHeight: primaryHeight)
        #expect(pointCG == CGPoint(x: -50, y: -20))
        #expect(Geometry.pointAppKit(fromCG: pointCG, primaryHeight: primaryHeight) == CGPoint(x: -50, y: 1100))
    }

    @Test func secondaryDisplayLeftOfPrimary() {
        let frameAppKit = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frameCG = Geometry.rectCG(fromAppKit: frameAppKit, primaryHeight: primaryHeight)
        #expect(frameCG == CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        #expect(Geometry.rectAppKit(fromCG: frameCG, primaryHeight: primaryHeight) == frameAppKit)
    }

    @Test func secondaryDisplayAbovePrimary() {
        let frameAppKit = CGRect(x: 0, y: 1080, width: 1920, height: 1200)
        let frameCG = Geometry.rectCG(fromAppKit: frameAppKit, primaryHeight: primaryHeight)
        #expect(frameCG == CGRect(x: 0, y: -1200, width: 1920, height: 1200))
        #expect(Geometry.rectAppKit(fromCG: frameCG, primaryHeight: primaryHeight) == frameAppKit)
    }

    @Test func displayLocalWithNegativeOrigin() {
        let displayFrameCG = CGRect(x: -1920, y: -1200, width: 1920, height: 1200)
        let rectCG = CGRect(x: -1900, y: -1180, width: 100, height: 50)
        let rectInDisplay = Geometry.rectInDisplay(fromCG: rectCG, displayFrameCG: displayFrameCG)
        #expect(rectInDisplay == CGRect(x: 20, y: 20, width: 100, height: 50))
        #expect(Geometry.rectCG(fromInDisplay: rectInDisplay, displayFrameCG: displayFrameCG) == rectCG)
    }

    @Test func viewToPixelsAt1x() {
        let rectPx = Geometry.rectPx(fromInView: CGRect(x: 10.4, y: 20.6, width: 100.2, height: 50),
                                     scale: 1, imageSizePx: CGSize(width: 1920, height: 1080))
        #expect(rectPx == CGRect(x: 10, y: 21, width: 101, height: 50))
    }

    @Test func viewToPixelsAt2x() {
        let rectPx = Geometry.rectPx(fromInView: CGRect(x: 10.25, y: 20, width: 100, height: 50),
                                     scale: 2, imageSizePx: CGSize(width: 3840, height: 2160))
        #expect(rectPx == CGRect(x: 21, y: 40, width: 200, height: 100))
    }

    @Test func viewToPixelsClampsToImage() {
        let sizePx = CGSize(width: 200, height: 100)
        #expect(Geometry.rectPx(fromInView: CGRect(x: -10, y: 40, width: 500, height: 500), scale: 2, imageSizePx: sizePx)
            == CGRect(x: 0, y: 80, width: 200, height: 20))
        #expect(Geometry.rectPx(fromInView: CGRect(x: 900, y: 900, width: 5, height: 5), scale: 2, imageSizePx: sizePx) == .zero)
    }

    @Test func pixelsRoundTripThroughViewAndGlobal() {
        let displayFrameCG = CGRect(x: -1920, y: -1200, width: 1920, height: 1200)
        let rectPx = CGRect(x: 40, y: 60, width: 200, height: 100)
        let rectInView = Geometry.rectInView(fromPx: rectPx, scale: 2)
        #expect(rectInView == CGRect(x: 20, y: 30, width: 100, height: 50))
        #expect(Geometry.rectPx(fromInView: rectInView, scale: 2, imageSizePx: CGSize(width: 3840, height: 2400)) == rectPx)
        #expect(Geometry.rectCG(fromPx: rectPx, displayFrameCG: displayFrameCG, scale: 2)
            == CGRect(x: -1900, y: -1170, width: 100, height: 50))
    }

    @Test func cropSizeAndTopLeftOrigin() throws {
        // 200x100 black image with a red 10x10 block in the top-left corner.
        let context = try #require(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 90, width: 10, height: 10)) // CGContext is bottom-left: y 90 = top
        let image = try #require(context.makeImage())

        let cropped = try #require(Geometry.crop(image, toPx: CGRect(x: 10, y: 20, width: 50, height: 30)))
        #expect(cropped.width == 50 && cropped.height == 30)

        let corner = try #require(Geometry.crop(image, toPx: CGRect(x: 0, y: 0, width: 10, height: 10)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        probe.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] > 200 && pixel[1] < 50)

        let clamped = try #require(Geometry.crop(image, toPx: CGRect(x: 180, y: 90, width: 50, height: 50)))
        #expect(clamped.width == 20 && clamped.height == 10)
        #expect(Geometry.crop(image, toPx: CGRect(x: 300, y: 300, width: 10, height: 10)) == nil)
    }
}
