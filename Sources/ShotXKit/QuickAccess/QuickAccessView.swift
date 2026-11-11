import SwiftUI

enum QuickAccessAction {
    /// `save` reveals the file in Finder when the item already has one.
    case copy, save, annotate, pin, share, close
}

/// State of one card; observed by `QuickAccessView`, mutated by `QuickAccessController`.
@Observable final class QuickAccessCard {
    var item: QuickAccessController.Item
    var thumbnail: NSImage
    /// Temporary PNG written for a drag when the image has no saved file.
    var dragTempURL: URL?
    /// A new identifier restarts the brief confirmation before dismissal.
    var copyFeedbackID: UUID?
    var isHovering = false
    var isDragging = false
    var isPresentingAction = false
    var idleID = UUID()
    /// How long the card waits untouched before closing; nil keeps it until closed.
    let idleDelay: Duration?

    enum Dismissal: Equatable {
        case paused, idle(UUID), copied(UUID)
    }

    var dismissalDelay: Duration? {
        switch dismissal {
        case .paused: nil
        case .idle: idleDelay
        case .copied: .milliseconds(800)
        }
    }

    var dismissal: Dismissal {
        if isPresentingAction || isDragging { return .paused }
        if let copyFeedbackID { return .copied(copyFeedbackID) }
        return isHovering ? .paused : .idle(idleID)
    }

    init(item: QuickAccessController.Item, thumbnail: NSImage, idleDelay: Duration?) {
        self.item = item
        self.thumbnail = thumbnail
        self.idleDelay = idleDelay
    }

    var fileURL: URL? {
        switch item {
        case .image(_, let url): url
        case .recording(let url): url
        }
    }

    var isRecording: Bool {
        if case .recording = item { true } else { false }
    }
}

/// One floating thumbnail card: image, drag source, and action buttons on hover.
struct QuickAccessView: View {
    static let cardSize = CGSize(width: 260, height: 180)
    private static let cornerRadius: CGFloat = 22

    let card: QuickAccessCard
    let dragFileURL: () -> URL?
    let onAction: (QuickAccessAction) -> Void
    private var showsActions: Bool { card.isHovering || card.copyFeedbackID != nil }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(nsImage: card.thumbnail)
                .resizable()
                .aspectRatio(contentMode: showsActions ? .fill : .fit)
                .frame(width: Self.cardSize.width - (showsActions ? 0 : 12),
                       height: Self.cardSize.height - (showsActions ? 0 : 12))
                .blur(radius: showsActions ? 18 : 0, opaque: true)
                .accessibilityLabel(card.isRecording ? "Recording preview" : "Screenshot preview")
            if showsActions {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.16, blue: 0.24).opacity(0.42), .black.opacity(0.38)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                    .allowsHitTesting(false)
            }
            DragSourceView(
                image: card.thumbnail, fileURL: dragFileURL,
                onHover: { card.isHovering = $0 }, onDropped: { onAction(.close) },
                onDragging: { card.isDragging = $0 }
            )
            if showsActions { buttons }
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.16), value: showsActions)
        .animation(.easeOut(duration: 0.18), value: card.copyFeedbackID)
        .task(id: card.dismissal) {
            let dismissal = card.dismissal
            guard let delay = card.dismissalDelay else { return }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // Interaction, another copy, or removal cancels the pending dismissal.
            }
            guard card.dismissal == dismissal else { return }
            onAction(.close)
        }
    }

    private var buttons: some View {
        ZStack {
            VStack(spacing: 8) {
                copyButton
                Button { onAction(.save) } label: {
                    Label("Save", systemImage: "arrow.down.to.line")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 108, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(QuickAccessSecondaryButtonStyle())
                .help(card.fileURL == nil ? "Save…" : "Reveal in Finder")
            }
            .offset(y: 4)
            VStack {
                HStack(spacing: 8) {
                    Label(card.isRecording ? "RECORDING" : "SCREENSHOT",
                          systemImage: card.isRecording ? "record.circle" : "viewfinder")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if !card.isRecording {
                        cornerButton("Pin to Screen", "pin.fill", .pin)
                    }
                    cornerButton("Close", "xmark", .close)
                }
                Spacer()
                HStack {
                    if !card.isRecording {
                        cornerButton("Annotate", "pencil", .annotate)
                    }
                    Spacer()
                    cornerButton("Share…", "square.and.arrow.up", .share)
                }
            }
            .padding(12)
        }
    }

    private var copyButton: some View {
        let copied = card.copyFeedbackID != nil
        return Button { onAction(.copy) } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? Color(red: 0.12, green: 0.44, blue: 0.3) : .black.opacity(0.75))
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? "Copied" : "Copy")
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 136, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(QuickAccessCopyButtonStyle(copied: copied))
        .help("Copy to Clipboard")
        .accessibilityLabel(copied ? "Copied to Clipboard" : "Copy to Clipboard")
    }

    private func cornerButton(_ title: String, _ symbol: String, _ action: QuickAccessAction) -> some View {
        Button { onAction(action) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(QuickAccessSecondaryButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct QuickAccessCopyButtonStyle: ButtonStyle {
    let copied: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black.opacity(0.9))
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(copied ? Color(red: 0.79, green: 0.95, blue: 0.86) : .white.opacity(0.94))
                    .opacity(configuration.isPressed ? 0.75 : 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct QuickAccessSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.9))
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0.1),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
