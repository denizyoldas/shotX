import CoreGraphics
import Foundation
import Testing
@testable import ShotXKit

struct WindowListTests {
    // Front to back: `front` overlaps the right half of `back`.
    let front = WindowInfo(id: 1, frameCG: CGRect(x: 100, y: 100, width: 200, height: 200), ownerPID: 10, title: "front")
    let back = WindowInfo(id: 2, frameCG: CGRect(x: 0, y: 0, width: 200, height: 200), ownerPID: 11, title: "back")
    var windows: [WindowInfo] { [front, back] }

    @Test func hitTestPrefersFrontmostInOverlap() {
        #expect(WindowList.hitTest(CGPoint(x: 150, y: 150), in: windows) == front)
        #expect(WindowList.hitTest(CGPoint(x: 150, y: 150), in: [back, front]) == back)
    }

    @Test func hitTestFindsWindowBehind() {
        #expect(WindowList.hitTest(CGPoint(x: 50, y: 50), in: windows) == back)
    }

    @Test func hitTestMisses() {
        #expect(WindowList.hitTest(CGPoint(x: 250, y: 50), in: windows) == nil)
        #expect(WindowList.hitTest(CGPoint(x: 50, y: 50), in: []) == nil)
    }

    @Test func hitTestEdgesAreMinInclusiveMaxExclusive() {
        #expect(WindowList.hitTest(CGPoint(x: 0, y: 0), in: windows) == back)
        #expect(WindowList.hitTest(CGPoint(x: 100, y: 100), in: windows) == front)
        #expect(WindowList.hitTest(CGPoint(x: 300, y: 300), in: windows) == nil)
        #expect(WindowList.hitTest(CGPoint(x: 299.5, y: 299.5), in: windows) == front)
    }

    @Test func hitTestHandlesNegativeCoordinates() {
        let left = WindowInfo(id: 3, frameCG: CGRect(x: -500, y: -300, width: 100, height: 100), ownerPID: 12, title: "left")
        #expect(WindowList.hitTest(CGPoint(x: -450, y: -250), in: windows + [left]) == left)
    }

    // MARK: parse

    func entry(
        id: Int = 7, pid: Int = 42, layer: Int = 0, alpha: Double? = 1,
        frameCG: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200), name: String? = "Doc", owner: String? = "App"
    ) -> [String: Any] {
        var entry: [String: Any] = [
            kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
            kCGWindowBounds as String: frameCG.dictionaryRepresentation,
        ]
        entry[kCGWindowAlpha as String] = alpha
        entry[kCGWindowName as String] = name
        entry[kCGWindowOwnerName as String] = owner
        return entry
    }

    @Test func parsesEntryAndKeepsOrder() {
        let parsed = WindowList.parse([entry(id: 7), entry(id: 8, pid: 43)], excludingPID: 1)
        #expect(parsed.map(\.id) == [7, 8])
        #expect(parsed[0] == WindowInfo(id: 7, frameCG: CGRect(x: 10, y: 20, width: 300, height: 200), ownerPID: 42, title: "Doc"))
    }

    @Test func titleFallsBackToOwnerName() {
        #expect(WindowList.parse([entry(name: nil)], excludingPID: 1)[0].title == "App")
        #expect(WindowList.parse([entry(name: "")], excludingPID: 1)[0].title == "App")
        #expect(WindowList.parse([entry(name: nil, owner: nil)], excludingPID: 1)[0].title == "")
    }

    @Test func filtersOwnPidLayerAlphaAndSize() {
        let side = WindowList.minimumSide
        let entries = [
            entry(id: 1, pid: 99),  // own process
            entry(id: 2, layer: 25),  // menu bar / dock / overlay level
            entry(id: 3, alpha: 0),  // invisible
            entry(id: 4, frameCG: CGRect(x: 0, y: 0, width: side - 1, height: 500)),  // sliver
            entry(id: 5, frameCG: CGRect(x: 0, y: 0, width: side, height: side)),  // smallest kept
            entry(id: 6, alpha: nil),  // missing alpha counts as opaque
        ]
        #expect(WindowList.parse(entries, excludingPID: 99).map(\.id) == [5, 6])
    }

    @Test func skipsMalformedEntries() {
        var noBounds = entry()
        noBounds[kCGWindowBounds as String] = nil
        #expect(WindowList.parse([noBounds, [:]], excludingPID: 1).isEmpty)
    }
}
