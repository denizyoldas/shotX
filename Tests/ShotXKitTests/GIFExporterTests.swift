import AVFoundation
import ImageIO
import Testing
@testable import ShotXKit

struct GIFExporterTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("shotx-gif-\(UUID().uuidString)")

    /// Writes a solid-colour 200×100 H.264 movie of `frames` frames at 30 fps.
    private func makeMovie(frames: Int) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("movie.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 200, AVVideoHeightKey: 100,
        ])
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: 200, height: 100)
        )
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            var pixels = try CVMutablePixelBuffer(attributes)
            pixels.accessUnsafeMutableRawPlaneBytes { planes in
                for plane in planes { plane.bytes.initializeMemory(as: UInt8.self, repeating: 0x80) }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(pixels), with: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        receiver.finish()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: 30))
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
        return url
    }

    @Test func exportsLoopingGIFAtRequestedRateAndWidth() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let movie = try await makeMovie(frames: 30)
        let gif = directory.appendingPathComponent("out.gif")
        try await GIFExporter.export(movie: movie, to: gif, fps: 10, maxWidth: 100)

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(abs(CGImageSourceGetCount(source) - 10) <= 1)

        let gifKey = kCGImagePropertyGIFDictionary as String
        let fileProperties = try #require(CGImageSourceCopyProperties(source, nil) as? [String: Any])
        let fileGIF = try #require(fileProperties[gifKey] as? [String: Any])
        #expect(fileGIF[kCGImagePropertyGIFLoopCount as String] as? Int == 0)

        let frameProperties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(frameProperties[kCGImagePropertyPixelWidth as String] as? Int == 100)
        #expect(frameProperties[kCGImagePropertyPixelHeight as String] as? Int == 50)
        let frameGIF = try #require(frameProperties[gifKey] as? [String: Any])
        let delay = try #require(frameGIF[kCGImagePropertyGIFDelayTime as String] as? Double)
        #expect(abs(delay - 0.1) < 0.001)
    }

    @Test func throwsForFileWithoutVideoTrack() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bogus = directory.appendingPathComponent("bogus.mp4")
        try Data("not a movie".utf8).write(to: bogus)
        await #expect(throws: (any Error).self) {
            try await GIFExporter.export(movie: bogus, to: directory.appendingPathComponent("x.gif"), fps: 10, maxWidth: 100)
        }
    }
}
