import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Converts a movie file to an endlessly looping GIF.
nonisolated enum GIFExporter {
    enum ExportError: LocalizedError {
        case invalidParameters(fps: Int, maxWidth: Int)
        case noVideoTrack(URL)
        case emptyMovie(URL)
        case destinationFailed(URL)

        var errorDescription: String? {
            switch self {
            case .invalidParameters(let fps, let maxWidth):
                "GIF export needs a positive frame rate and width (got \(fps) fps, \(maxWidth) px)."
            case .noVideoTrack(let url): "\(url.lastPathComponent) has no video track."
            case .emptyMovie(let url): "\(url.lastPathComponent) has no video frames."
            case .destinationFailed(let url): "Could not write the GIF to \(url.path)."
            }
        }
    }

    @concurrent static func export(movie: URL, to destination: URL, fps: Int, maxWidth: Int) async throws {
        guard fps > 0, maxWidth > 0 else { throw ExportError.invalidParameters(fps: fps, maxWidth: maxWidth) }

        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack(movie)
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let orientedPx = naturalSize.applying(transform)
        let widthPx = abs(orientedPx.width), heightPx = abs(orientedPx.height)
        guard duration.isFinite, duration > 0, widthPx > 0, heightPx > 0 else { throw ExportError.emptyMovie(movie) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let scale = min(1, CGFloat(maxWidth) / widthPx)
        generator.maximumSize = CGSize(width: (widthPx * scale).rounded(.down), height: (heightPx * scale).rounded(.up))

        let frameCount = max(1, Int((duration * Double(fps)).rounded()))
        guard let gif = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { throw ExportError.destinationFailed(destination) }

        let gifKey = kCGImagePropertyGIFDictionary as String
        CGImageDestinationSetProperties(gif, [gifKey: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let delay = 1.0 / Double(fps)
        let frameProperties = [gifKey: [
            kCGImagePropertyGIFDelayTime as String: delay,
            kCGImagePropertyGIFUnclampedDelayTime as String: delay,
        ]] as CFDictionary

        // ponytail: ImageIO holds every frame in memory until finalize (fine for short clips);
        // switch to a streaming GIF encoder or cap duration if long recordings exhaust memory.
        for index in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            let frame = try await generator.image(at: time).image
            CGImageDestinationAddImage(gif, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(gif) else { throw ExportError.destinationFailed(destination) }
    }
}
