import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    var onShortcutRecordingChanged: (Bool) -> Void = { _ in }

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNote: String?
    @State private var recordingShortcut: AppAction?

    /// Opening settings by global shortcut is pointless; everything else gets a row.
    private static let shortcutActions = AppAction.allCases.filter { $0 != .openSettings }
    /// 0 = never close automatically. Hovering or using a card always pauses the countdown.
    static let quickAccessDurations = [5, 10, 30, 60, 0]

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Recording", systemImage: "record.circle") { recording }
            Tab("Shortcuts", systemImage: "keyboard") { shortcuts }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
        .onChange(of: recordingShortcut) { onShortcutRecordingChanged(recordingShortcut != nil) }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let launchNote {
                    Text(launchNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Screenshots") {
                LabeledContent("Save to") {
                    Text((settings.saveDirectory.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.saveDirectory.path)
                    Button("Choose…", action: chooseSaveDirectory)
                }
                Picker("Format", selection: $settings.imageFormat) {
                    Text("PNG").tag(ImageFormat.png)
                    Text("JPEG").tag(ImageFormat.jpeg)
                }
                .pickerStyle(.segmented)
            }
            Section("After capture") {
                Toggle("Copy to clipboard", isOn: $settings.copyAfterCapture)
                Toggle("Save to folder", isOn: $settings.saveAfterCapture)
                Toggle("Show Quick Access preview", isOn: $settings.showQuickAccess)
                Picker("Close preview after", selection: $settings.quickAccessSeconds) {
                    ForEach(Self.quickAccessDurations, id: \.self) { seconds in
                        Text(seconds == 0 ? "Never" : Duration.seconds(seconds).formatted(.units(width: .wide)))
                            .tag(seconds)
                    }
                }
                .disabled(!settings.showQuickAccess)
            }
        }
    }

    private var recording: some View {
        Form {
            Section("Video") {
                Picker("Format", selection: $settings.recordingFormat) {
                    Text("MP4").tag(RecordingFormat.mp4)
                    Text("GIF").tag(RecordingFormat.gif)
                }
                .pickerStyle(.segmented)
                Picker("Frame rate", selection: $settings.recordingFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
            }
            Section("Audio") {
                Toggle("Microphone", isOn: $settings.recordMicrophone)
                Toggle("System audio", isOn: $settings.recordSystemAudio)
            }
            Section("GIF") {
                Stepper("Frame rate: \(settings.gifFPS) fps", value: $settings.gifFPS, in: 5...30, step: 5)
                Stepper("Max width: \(settings.gifMaxWidth) px", value: $settings.gifMaxWidth, in: 200...1920, step: 100)
            }
        }
    }

    private var shortcuts: some View {
        Form {
            Section {
                ForEach(Self.shortcutActions, id: \.self) { action in
                    LabeledContent(action.title) {
                        HotKeyRecorderView(settings: settings, action: action, recording: $recordingShortcut)
                        Button("Clear", systemImage: "xmark.circle.fill") { settings.setHotKey(nil, for: action) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(settings.hotKeys[action] == nil)
                            .help("Clear shortcut")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("While shotX uses ⇧⌘3, ⇧⌘4 or ⇧⌘5, macOS's own screenshot shortcut for that key "
                        + "is switched off. It comes back when you change the shortcut or quit shotX.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Use ⇧⌘3 / ⇧⌘4 / ⇧⌘5") {
                            recordingShortcut = nil
                            settings.hotKeys.merge(Settings.macOSScreenshotHotKeys) { $1 }
                        }
                        .help("Fullscreen ⇧⌘3, area ⇧⌘4, record area ⇧⌘5")
                        Spacer()
                        Button("Restore defaults") {
                            recordingShortcut = nil
                            settings.hotKeys = Settings.defaultHotKeys
                        }
                    }
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchNote = nil
        } catch {
            log.error("launch at login: \(error.localizedDescription, privacy: .public)")
            launchNote = "Could not change the login item (\(error.localizedDescription)). "
                + "It only works from the signed app installed in ~/Applications (make install)."
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}
