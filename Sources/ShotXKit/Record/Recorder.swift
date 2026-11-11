import AVFoundation
import Observation
import ScreenCaptureKit

/// Records a display (or part of one) to an MP4 in the temp directory; the coordinator moves it.
/// ScreenCaptureKit writes the file itself (`SCRecordingOutput`): H.264 video plus the audio the
/// stream configuration captures (system audio and/or microphone).
///
/// States: idle → starting → recording → (stop requested | stream ended) → idle.
/// A session is finalized exactly once, by whichever comes first: the recording output's
/// finish/failure callback, or a deadline armed once the stream is known to have ended.
@Observable
final class Recorder {
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case emptyArea
        case notFinalized

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "A recording is already in progress."
            case .emptyArea: "The recording area is outside the display."
            case .notFinalized: "The recording file could not be finalized."
            }
        }
    }

    private(set) var isRecording = false

    /// Called with the finished temporary MP4 when recording ends without `stop()`
    /// (e.g. the user stops it from the system UI).
    @ObservationIgnored var onExternalStop: ((URL) -> Void)?

    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private let areaFrame = RecordingAreaFrame()

    /// How long to wait for the file-finished callback after the stream has ended.
    private static let finalizeDeadline: Duration = .seconds(15)

    func start(_ target: RecordingTarget, options: RecordingOptions) async throws {
        guard session == nil, !isStarting else { throw RecorderError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }

        let displayID: CGDirectDisplayID
        let areaCG: CGRect?
        switch target {
        case .display(let id): (displayID, areaCG) = (id, nil)
        case .area(let rectCG, let id): (displayID, areaCG) = (id, rectCG)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ShotXError.noDisplay }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        var sizePoints = filter.contentRect.size
        if let areaCG {
            let displayFrameCG = CGDisplayBounds(displayID)
            let rectInDisplay = Geometry.rectInDisplay(fromCG: areaCG, displayFrameCG: displayFrameCG)
                .intersection(CGRect(origin: .zero, size: displayFrameCG.size))
            guard !rectInDisplay.isEmpty else { throw RecorderError.emptyArea }
            config.sourceRect = rectInDisplay
            sizePoints = rectInDisplay.size
        }
        let sizePx = Self.evenPixelSize(points: sizePoints, scale: CGFloat(filter.pointPixelScale))
        config.width = sizePx.width
        config.height = sizePx.height
        config.captureResolution = .best
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.fps)))
        config.showsCursor = true
        config.capturesAudio = options.captureSystemAudio
        config.excludesCurrentProcessAudio = options.captureSystemAudio
        config.captureMicrophone = options.captureMicrophone

        let url = FileManager.default.temporaryDirectory.appending(path: "shotX-\(UUID().uuidString).mp4")
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.videoCodecType = .h264
        recordingConfig.outputFileType = .mp4

        let (events, continuation) = AsyncStream.makeStream(of: RecorderEvent.self)
        let relay = RecorderRelay(events: continuation)
        let stream = SCStream(filter: filter, configuration: config, delegate: relay)
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: relay)
        // Added before startCapture so the first captured frame is in the file.
        try stream.addRecordingOutput(output)
        // ponytail: a failed start can leave an empty temp file behind; the system purges the temp directory.
        try await stream.startCapture()

        let session = Session(stream: stream, output: output, relay: relay, events: continuation, url: url)
        self.session = session
        isRecording = true
        if let areaCG { areaFrame.show(areaCG: areaCG, displayFrameCG: CGDisplayBounds(displayID)) }
        // Events that arrived during startCapture are buffered in the stream, in order.
        Task { [weak self] in
            for await event in events { self?.handle(event, in: session) }
        }
    }

    /// Finishes the file and returns its temporary URL.
    func stop() async throws -> URL {
        guard let session, !session.stopRequested else { throw ShotXError.notRecording }
        session.stopRequested = true
        do {
            try await session.stream.stopCapture()
        } catch {
            // Expected when the stream already ended on its own; the file still gets finalized.
            log.info("Recorder: stopCapture: \(error.localizedDescription, privacy: .public)")
        }
        armDeadline(for: session)
        return try await withCheckedThrowingContinuation { continuation in
            if let outcome = session.outcome {
                continuation.resume(with: outcome)
            } else {
                session.stopWaiter = continuation
            }
        }
    }

    /// Content size in pixels, rounded, then forced down to even width and height (H.264 requirement).
    nonisolated static func evenPixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ points: CGFloat) -> Int { max(2, Int((points * scale).rounded()) & ~1) }
        return (even(points.width), even(points.height))
    }

    // MARK: Session events (main actor)

    private func handle(_ event: RecorderEvent, in session: Session) {
        guard self.session === session else { return }
        switch event {
        case .started:
            log.info("Recorder: recording started")
        case .finished:
            finalize(session, error: nil)
        case .failed(let error):
            // The stream may still be capturing (e.g. disk full); do not leave it running.
            if !session.stopRequested { session.stream.stopCapture { _ in } }
            finalize(session, error: error)
        case .streamStopped(let error):
            log.info("Recorder: stream stopped: \(error.localizedDescription, privacy: .public)")
            armDeadline(for: session)
        }
    }

    /// Safety net: if the file-finished callback never arrives after the stream ended, decide by the file itself.
    private func armDeadline(for session: Session) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.finalizeDeadline)
            guard self?.session === session else { return }
            let isPlayable = (try? await AVURLAsset(url: session.url).load(.isPlayable)) ?? false
            self?.finalize(session, error: isPlayable ? nil : RecorderError.notFinalized)
        }
    }

    /// Ends the session exactly once; later calls for the same session are no-ops.
    private func finalize(_ session: Session, error: (any Error)?) {
        guard self.session === session else { return }
        self.session = nil
        isRecording = false
        areaFrame.hide() // every way a recording ends comes through here
        session.events.finish()
        let outcome: Result<URL, any Error> = error.map { .failure($0) } ?? .success(session.url)
        session.outcome = outcome

        if let waiter = session.stopWaiter {
            session.stopWaiter = nil
            waiter.resume(with: outcome)
        } else if !session.stopRequested {
            switch outcome {
            case .success(let url): onExternalStop?(url)
            case .failure(let error): log.error("Recorder: recording failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Otherwise stop() is still inside stopCapture and picks up `outcome` when it returns.
    }
}

/// One recording, from a successful `startCapture` until `finalize`.
private final class Session {
    let stream: SCStream
    let output: SCRecordingOutput  // retained for the stream
    let relay: RecorderRelay       // retained: SCK does not own its delegates
    let events: AsyncStream<RecorderEvent>.Continuation
    let url: URL
    var stopRequested = false
    var stopWaiter: CheckedContinuation<URL, any Error>?
    var outcome: Result<URL, any Error>?

    init(stream: SCStream, output: SCRecordingOutput, relay: RecorderRelay,
         events: AsyncStream<RecorderEvent>.Continuation, url: URL) {
        self.stream = stream
        self.output = output
        self.relay = relay
        self.events = events
        self.url = url
    }
}

private nonisolated enum RecorderEvent: Sendable {
    case started
    case finished
    case failed(any Error)
    case streamStopped(any Error)
}

/// SCK calls these on its own queues; they only forward into a Sendable stream that the main actor drains in order.
private nonisolated final class RecorderRelay: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private let events: AsyncStream<RecorderEvent>.Continuation

    init(events: AsyncStream<RecorderEvent>.Continuation) {
        self.events = events
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        events.yield(.streamStopped(error))
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        events.yield(.started)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        events.yield(.failed(error))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        events.yield(.finished)
    }
}
