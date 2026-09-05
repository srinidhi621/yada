import SwiftUI
import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation")
}

@main
struct YadaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var controller = makeAppController()
    @State private var language = LanguageSetup()
    var body: some Scene {
        Window("Yada", id: "yada") {
            MainView(controller: controller, language: language, delegate: delegate)
        }
        .defaultSize(width: 600, height: 700)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuContent(controller: controller, language: language)
        } label: {
            StatusLabel(controller: controller)
        }
    }
}


struct MainView: View {
    let controller: SessionController
    let language: LanguageSetup
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dictation", systemImage: "waveform", value: 0) {
                ContentView(controller: controller, language: language)
            }
            Tab("Recent transcripts", systemImage: "clock", value: 1) {
                HistoryView(history: controller.history)
            }
        }
        .onAppear {
            delegate.configure(controller: controller, language: language) {
                selectedTab = 0
                openWindow(id: "yada")
                NSApp.activate()
            }
        }
    }
}

struct StatusLabel: View {
    let controller: SessionController
    var body: some View {
        Label("Yada · \(controller.state.rawValue)", systemImage: controller.state == .recording ? "mic.fill" : "waveform")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SessionController?
    private var showWindow: (() -> Void)?
    private let pill = RecordingPill()

    func configure(controller: SessionController, language: LanguageSetup, showWindow: @escaping () -> Void) {
        self.showWindow = showWindow
        guard self.controller == nil else { return }
        self.controller = controller
        if !UIValidation.isEnabled {
            KeyboardShortcuts.removeHandler(for: .toggleDictation)
            KeyboardShortcuts.onKeyDown(for: .toggleDictation) {
                controller.handleShortcut(locale: language.locale,
                    setupBusy: language.checking || language.downloading,
                    capture: { ActiveFieldInsertion.capture() })
                if controller.needsAccessibility { ActiveFieldInsertion.requestAccessibility() }
            }
        }
        observeState()
    }

    private func observeState() {
        guard let controller else { return }
        let state = withObservationTracking { controller.state } onChange: {
            Task { @MainActor [weak self] in self?.observeState() }
        }
        pill.update(controller: controller)
        if (state == .ready && controller.shouldPresentPreview) || state == .outcomeUnknown || state == .failure { showWindow?() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow?()
        return true
    }
}

struct MenuContent: View {
    let controller: SessionController
    let language: LanguageSetup
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(controller.state.rawValue)
        Button("Show Yada") { openWindow(id: "yada"); NSApp.activate() }
        Button(controller.state == .recording ? "Stop and finalize" : "Start recording") {
            controller.toggle(locale: language.locale)
        }.disabled(language.checking || language.downloading || controller.cleaningUp || [.finalizing, .delivering].contains(controller.state))
        if controller.canCancel { Button("Cancel recording") { controller.cancel() } }
        Divider()
        Menu("Recent transcripts") {
            if controller.history.entries.isEmpty { Text("No saved transcripts yet") }
            ForEach(controller.history.entries.prefix(8)) { entry in
                Button(String(entry.text.prefix(60))) {
                    controller.showSaved(entry)
                    openWindow(id: "yada")
                    NSApp.activate()
                }.disabled(controller.busy)
            }
        }
        Button("Quit Yada") { NSApp.terminate(nil) }
    }
}

struct ContentView: View {
    @Bindable var controller: SessionController
    @Bindable var language: LanguageSetup
    @State private var copyStatus = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if UIValidation.isEnabled { Text("UI preview · synthetic audio levels · no microphone").font(.caption).foregroundStyle(.orange) }
            HStack {
                Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text("Yada").font(.largeTitle.bold())
                    Text("Speak where you type.").foregroundStyle(.secondary)
                }
                Spacer()
                Label(controller.state.rawValue, systemImage: controller.state == .recording ? "record.circle.fill" : "circle")
                    .foregroundStyle(controller.state == .recording ? .red : .secondary)
                    .accessibilityIdentifier("sessionStatus")
            }
            GroupBox("Setup") {
                VStack(alignment: .leading, spacing: 10) {
                    KeyboardShortcuts.Recorder("Recording shortcut", name: .toggleDictation)
                        .shortcutValidation { shortcut in
                            if shortcut.key == .function || shortcut.modifiers.contains(.function) {
                                return .disallow(reason: "Keep Fn available for Wispr Flow. Choose another chord.")
                            }
                            return .allow
                        }
                    Text("Press your shortcut to start. Press it again to stop and insert at the cursor. Wispr Flow keeps Fn.").font(.caption).foregroundStyle(.secondary)
                    Picker("Speech language", selection: $language.selectedID) {
                        if !language.locales.contains(where: { $0.identifier == language.selectedID }) {
                            Text(language.selectedID).tag(language.selectedID)
                        }
                        ForEach(language.locales, id: \.identifier) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                        }
                    }
                    HStack {
                        Button("Check language") { Task { await language.check() } }
                        Button("Download language") { Task { await language.download() } }
                            .disabled(language.installed || language.locales.isEmpty)
                    }
                    Text(language.status).font(.caption).fixedSize(horizontal: false, vertical: true)
                    if language.downloading { ProgressView(value: language.progress).accessibilityLabel("Language download progress") }
                }.padding(6)
            }.disabled(controller.busy || language.checking || language.downloading || UIValidation.isEnabled)
            Text(controller.message).fixedSize(horizontal: false, vertical: true)
            if controller.needsAccessibility {
                Button("Allow text insertion") { ActiveFieldInsertion.requestAccessibility() }
            }
            if let error = controller.history.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if controller.state == .preparing || controller.state == .finalizing || controller.state == .delivering { ProgressView().controlSize(.small) }
            if controller.state == .recording {
                ProgressView(value: Double(controller.level)).tint(.red).accessibilityLabel("Microphone level")
            }
            HStack {
                Button(controller.state == .recording ? "Stop and finalize" : "Start recording") {
                    copyStatus = ""
                    controller.toggle(locale: language.locale)
                }
                .buttonStyle(.borderedProminent)
                .disabled(language.checking || language.downloading || controller.cleaningUp || [.preparing, .finalizing, .delivering].contains(controller.state))
                if controller.canCancel { Button("Cancel") { controller.cancel() }.disabled(controller.cleaningUp) }
                Spacer()
            }
            GroupBox(controller.state == .ready ? "Final transcript" : "Preview · may change") {
                ScrollView {
                    Text(controller.transcript.preview.isEmpty ? "Your words will appear here." : controller.transcript.preview)
                        .foregroundStyle(controller.transcript.preview.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }.frame(minHeight: 120, maxHeight: .infinity)
            }
            HStack {
                Button("Copy") {
                    copyStatus = copyLocally(controller.transcript.finalText)
                }.disabled(!controller.canCopy)
                Button("Clear") { controller.clear(); copyStatus = "" }.disabled(controller.busy)
                Text(copyStatus).font(.caption)
                Spacer()
            }
            Text("Audio is never saved. The last 50 finalized transcripts are saved locally; manage them in Recent transcripts. Text goes directly into supported fields. Copy is available when insertion cannot be verified. Local clipboard managers may still read or sync copied text. ASR may normalize speech; Yada adds no cleanup.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let ready = controller.readinessMS {
                Text("Capture readiness: \(Int(ready)) ms" + (controller.finalizationMS.map { " · Finalization: \(Int($0)) ms" } ?? ""))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 600)
        .task { if !UIValidation.isEnabled { await language.check() } }
        .onChange(of: controller.state) { _, _ in copyStatus = "" }
    }
}

@MainActor
func copyLocally(_ text: String) -> String {
    NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
    return NSPasteboard.general.setString(text, forType: .string) ? "Copied on this Mac." : "Copy failed. Please retry."
}

struct HistoryView: View {
    let history: RecentTranscripts
    @State private var selectedID: UUID?
    @State private var copyStatus = ""
    @State private var confirmClear = false
    private var selected: SavedTranscript? { history.entries.first { $0.id == selectedID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent transcripts").font(.title2.bold())
            Text("The last 50 finalized transcripts, saved on this Mac. Audio is never saved.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = history.errorMessage { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if history.entries.isEmpty {
                ContentUnavailableView("No saved transcripts", systemImage: "clock", description: Text("Completed dictation will appear here. Cancelled recordings are discarded."))
            } else {
                List(history.entries, selection: $selectedID) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Text(entry.text).lineLimit(2)
                    }.tag(entry.id).padding(.vertical, 4)
                }.frame(minHeight: 130)
                if let selected {
                    ScrollView { Text(selected.text).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                        .frame(minHeight: 100, maxHeight: 200)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("Copy") { copyStatus = copyLocally(selected.text) }
                        Button("Delete", role: .destructive) { history.delete(id: selected.id); selectedID = nil; copyStatus = "" }
                        Text(copyStatus).font(.caption)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("Local clipboard managers may read or sync copied text.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear history", role: .destructive) { confirmClear = true }
                    .disabled(history.entries.isEmpty && history.errorMessage == nil)
            }
        }.padding(24).frame(minWidth: 500, minHeight: 600)
        .onChange(of: selectedID) { _, _ in copyStatus = "" }
        .confirmationDialog("Delete all saved transcripts?", isPresented: $confirmClear) {
            Button("Delete all", role: .destructive) { history.clear(); selectedID = nil; copyStatus = "" }
        } message: { Text("This removes Yada's saved history. Text already copied elsewhere is unaffected.") }
    }
}

// A debug-only driver exercises the real views/controller without microphone or user history.
enum UIValidation {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        false
        #endif
    }
}

@MainActor
private func makeAppController() -> SessionController {
    #if DEBUG
    if UIValidation.isEnabled {
        return SessionController { PreviewRecognition() }
    }
    #endif
    let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    return SessionController(history: RecentTranscripts(fileURL: testing ? nil : RecentTranscripts.defaultURL))
}

#if DEBUG
@MainActor
private final class PreviewRecognition: RecognitionSession {
    private var levels: Task<Void, Never>?
    private var result: (@MainActor (TranscriptSegment) -> Void)?
    func start(locale: Locale, onResult: @escaping @MainActor (TranscriptSegment) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        result = onResult
        try await Task.sleep(for: .milliseconds(700))
        levels = Task {
            let samples: [Float] = [0.1, 0.3, 0.7, 0.9, 0.4, 0.2]
            var index = 0
            while !Task.isCancelled {
                onLevel(samples[index % samples.count])
                index += 1
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
    func stop() async throws {
        levels?.cancel()
        try await Task.sleep(for: .milliseconds(700))
        result?(TranscriptSegment(start: 0, end: 1, text: "Synthetic preview transcript. No microphone was used.", isFinal: true))
    }
    func cancel() async { levels?.cancel() }
}
#endif
