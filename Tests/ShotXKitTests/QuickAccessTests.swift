import AppKit
import Testing
@testable import ShotXKit

@MainActor @Test func quickAccessCardsStackUpwardFromBottomLeft() {
    let visible = CGRect(x: 100, y: 50, width: 1440, height: 800)
    let first = QuickAccessController.cardFrameAppKit(index: 0, visibleFrameAppKit: visible)
    let second = QuickAccessController.cardFrameAppKit(index: 1, visibleFrameAppKit: visible)

    #expect(first.origin == CGPoint(x: 116, y: 66))
    #expect(first.size == QuickAccessView.cardSize)
    #expect(second.minX == first.minX)
    #expect(second.minY == first.maxY + QuickAccessController.spacing)
}

@Test func dragImageRectKeepsAspectRatioAndIsCentred() {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 130)
    #expect(DragSourceView.aspectFitRect(size: CGSize(width: 400, height: 100), in: bounds)
        == CGRect(x: 0, y: 40, width: 200, height: 50))
    #expect(DragSourceView.aspectFitRect(size: CGSize(width: 100, height: 260), in: bounds)
        == CGRect(x: 75, y: 0, width: 50, height: 130))
    #expect(DragSourceView.aspectFitRect(size: .zero, in: bounds) == bounds)
}

@MainActor @Test(arguments: [CGFloat(600), 800, 1200])
func quickAccessStackFitsWithinVisibleScreen(height: CGFloat) {
    let visible = CGRect(x: 100, y: 50, width: 1440, height: height)
    let capacity = QuickAccessController.cardCapacity(visibleFrameAppKit: visible)
    let topCard = QuickAccessController.cardFrameAppKit(index: capacity - 1, visibleFrameAppKit: visible)
    #expect(capacity >= 1 && capacity <= QuickAccessController.maxCards)
    #expect(topCard.maxY <= visible.maxY - QuickAccessController.margin)
    if capacity < QuickAccessController.maxCards {
        let overflow = QuickAccessController.cardFrameAppKit(index: capacity, visibleFrameAppKit: visible)
        #expect(overflow.maxY > visible.maxY - QuickAccessController.margin)
    }
}

@MainActor @Test func quickAccessCardClosesAfterConfiguredDelay() {
    let item = QuickAccessController.Item.recording(URL(fileURLWithPath: "/tmp/a.mp4"))
    let card = QuickAccessCard(item: item, thumbnail: NSImage(), idleDelay: .seconds(30))
    #expect(card.dismissalDelay == .seconds(30))
    card.isHovering = true
    #expect(card.dismissalDelay == nil)
    card.isHovering = false
    card.copyFeedbackID = UUID()
    #expect(card.dismissalDelay == .milliseconds(800))  // copy confirmation still closes, even with "Never"
    #expect(QuickAccessCard(item: item, thumbnail: NSImage(), idleDelay: nil).dismissalDelay == nil)
}
