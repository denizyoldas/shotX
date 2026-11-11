import CoreGraphics
import Testing
@testable import ShotXKit

@Suite struct RecorderTests {
    @Test func pixelSizeIsScaledAndEven() {
        #expect(Recorder.evenPixelSize(points: CGSize(width: 1512, height: 982), scale: 2) == (3024, 1964))
        #expect(Recorder.evenPixelSize(points: CGSize(width: 301, height: 199), scale: 1) == (300, 198))
        #expect(Recorder.evenPixelSize(points: CGSize(width: 100.5, height: 50.25), scale: 2) == (200, 100))
        #expect(Recorder.evenPixelSize(points: CGSize(width: 0.4, height: 1), scale: 1) == (2, 2))
    }

    @Test @MainActor func stopWhenIdleThrowsNotRecording() async {
        let recorder = Recorder()
        await #expect(throws: ShotXError.self) { _ = try await recorder.stop() }
        #expect(!recorder.isRecording)
    }
}
