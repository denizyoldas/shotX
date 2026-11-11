import CoreGraphics
import Vision

/// Vision text recognition; top candidate of each line, joined with newlines in Vision's reading order.
nonisolated enum TextRecognizer {
    @concurrent static func recognize(_ image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
