import AppKit
import Testing
@testable import ShotXKit

@MainActor
struct AppTests {
    private func rect(_ query: String) -> CGRect? {
        AppDelegate.captureAreaRectCG(from: URL(string: "shotx://capture-area?\(query)")!)
    }

    @Test func captureAreaURLParsesGlobalRect() {
        #expect(rect("x=100&y=-50.5&w=300&h=200") == CGRect(x: 100, y: -50.5, width: 300, height: 200))
    }

    @Test(arguments: ["x=1&y=2&w=3", "x=1&y=2&w=0&h=4", "x=1&y=2&w=3&h=-4", "x=nan&y=2&w=3&h=4",
                      "x=1&y=inf&w=3&h=4", "x=a&y=2&w=3&h=4", ""])
    func captureAreaURLRejects(query: String) {
        #expect(rect(query) == nil)
    }

    private func key(_ keyCode: UInt32) -> String {
        StatusItemController.keyEquivalent(for: HotKey(keyCode: keyCode, modifiers: [.control, .option]))
    }

    private func functionKey(_ value: Int) -> String {
        String(Character(Unicode.Scalar(UInt32(value))!))
    }

    @Test func menuKeyEquivalentMatchesHotKey() {
        #expect(key(0) == "a")                                   // A
        #expect(key(49) == " ")                                  // Space
        #expect(key(36) == "\r")                                 // ↩
        #expect(key(96) == functionKey(NSF5FunctionKey))         // F5
        #expect(key(111) == functionKey(NSF12FunctionKey))       // F12
        #expect(key(123) == functionKey(NSLeftArrowFunctionKey)) // ←
        #expect(key(200) == "")                                  // no name: menu shows no shortcut
    }
}
