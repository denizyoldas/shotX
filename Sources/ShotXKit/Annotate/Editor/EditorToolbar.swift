import SwiftUI

/// Tools, colour and width presets, undo/redo and the output actions, in one row above the canvas.
struct EditorToolbar: View {
    let session: EditorSession

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    iconButton(tool.title, symbol: tool.symbol, selected: session.tool == tool) { session.choose(tool) }
                }
            }
            Divider().frame(height: 18)
            HStack(spacing: 4) {
                ForEach(EditorSession.palette, id: \.name) { entry in
                    swatch(entry.name, color: entry.color)
                }
            }
            Divider().frame(height: 18)
            HStack(spacing: 2) {
                ForEach(EditorSession.presets, id: \.name) { preset in
                    widthButton(preset)
                }
            }
            Divider().frame(height: 18)
            iconButton("Undo", symbol: "arrow.uturn.backward", selected: false) { session.document.undo() }
                .disabled(!session.document.canUndo)
            iconButton("Redo", symbol: "arrow.uturn.forward", selected: false) { session.document.redo() }
                .disabled(!session.document.canRedo)
            Spacer(minLength: 8)
            if session.document.cropRectPx != nil {
                Button("Reset Crop") { session.document.setCrop(nil) }
            }
            Button("Copy") { session.copy() }
                .help("Copy the result (⌘C)")
            Button("Save…") { session.save() }
                .help("Save the result (⌘S)")
            Button("Done") { session.copy(thenClose: true) }
                .buttonStyle(.borderedProminent)
                .help("Copy the result and close")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func iconButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 24)
                .background(selected ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ name: String, color: CGColor) -> some View {
        let selected = session.style.color == color
        return Button { session.apply(color: color) } label: {
            Circle()
                .fill(Color(cgColor: color))
                .overlay(Circle().strokeBorder(.secondary, lineWidth: 0.5))
                .frame(width: 14, height: 14)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func widthButton(_ preset: EditorSession.StylePreset) -> some View {
        let selected = session.style.lineWidthPx == preset.lineWidth * session.document.scale
        return Button { session.apply(preset) } label: {
            Capsule()
                .frame(width: 16, height: preset.lineWidth)
                .frame(width: 26, height: 24)
                .background(selected ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(preset.name) line and text")
        .accessibilityLabel("\(preset.name) line and text")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
