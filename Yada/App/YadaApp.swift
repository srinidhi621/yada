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
    var body: some Scene {
        Window("Yada", id: "yada") {
            MainView(controller: delegate.controller, language: delegate.language, meeting: delegate.meeting, delegate: delegate)
        }
        .defaultSize(width: 600, height: 700)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuContent(controller: delegate.controller, language: delegate.language, meeting: delegate.meeting)
        } label: {
            StatusLabel(controller: delegate.controller, meeting: delegate.meeting)
        }
    }
}


struct MainView: View {
    let controller: SessionController
    let language: LanguageSetup
    let meeting: MeetingController
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dictation", systemImage: "waveform", value: 0) {
                ContentView(controller: controller, language: language, meeting: meeting)
            }
            Tab("Meetings", systemImage: "person.2.wave.2", value: 2) {
                MeetingView(meeting: meeting, dictation: controller, language: language)
            }
            Tab("Recent transcripts", systemImage: "clock", value: 1) {
                HistoryView(history: controller.history)
            }
        }
        .onAppear {
            delegate.setShowWindow {
                selectedTab = meeting.state == .failed ? 2 : 0
                openWindow(id: "yada")
                NSApp.activate()
            }
        }
    }
}

struct StatusLabel: View {
    let controller: SessionController
    let meeting: MeetingController
    var body: some View {
        Label(meeting.busy ? "Meeting · \(meeting.state.rawValue)" : "Yada · \(controller.state.rawValue)", systemImage: meeting.capturing || controller.state == .recording ? "mic.fill" : "waveform")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = makeAppController()
    let language = LanguageSetup()
    let meeting = MeetingController()
    private var showWindow: (() -> Void)?
    private let pill = RecordingPill()
    private let instance = AppInstance()
    private var mayConfigure = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !UIValidation.isEnabled,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do {
            mayConfigure = try instance.acquire()
        } catch {
            mayConfigure = false
            let alert = NSAlert()
            alert.messageText = "Yada could not start"
            alert.informativeText = SessionController.userMessage(error)
            alert.runModal()
        }
        if !mayConfigure { NSApp.terminate(nil) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard mayConfigure else { return }
        if !UIValidation.isEnabled && !UIValidation.isTesting {
            configureShortcut()
        }
        observeState()
        observeMeeting()
    }

    func setShowWindow(_ showWindow: @escaping () -> Void) {
        self.showWindow = showWindow
    }

    private func configureShortcut() {
        if KeyboardShortcuts.getShortcut(for: .toggleDictation) == nil {
            KeyboardShortcuts.setShortcut(.init(.y, modifiers: [.control]), for: .toggleDictation)
        }
        KeyboardShortcuts.removeHandler(for: .toggleDictation)
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [self] in
            guard !meeting.busy else { showWindow?(); return }
            if !controller.busy && (language.checking || language.downloading) {
                showWindow?()
                return
            }
            controller.handleShortcut(locale: language.locale,
                setupBusy: language.checking || language.downloading,
                capture: { ActiveFieldInsertion.capture() })
        }
        checkShortcut()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkShortcut()
    }

    private func checkShortcut() {
        guard mayConfigure, !UIValidation.isEnabled, !UIValidation.isTesting else { return }
        KeyboardShortcuts.enable(.toggleDictation)
        controller.shortcutIssue = KeyboardShortcuts.isEnabled(for: .toggleDictation) ? nil :
            "Yada could not register its global shortcut. Another app may be using it. Close the conflicting app, then return to Yada to retry."
    }

    private func observeState() {
        let state = withObservationTracking { controller.state } onChange: {
            Task { @MainActor [weak self] in self?.observeState() }
        }
        pill.update(controller: controller)
        if state == .formatting || (state == .ready && controller.shouldPresentPreview) || state == .outcomeUnknown || state == .failure { showWindow?() }
    }

    private func observeMeeting() {
        let state = withObservationTracking { meeting.state } onChange: {
            Task { @MainActor [weak self] in self?.observeMeeting() }
        }
        if state == .failed { showWindow?() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard meeting.busy else { return .terminateNow }
        Task { await meeting.finishForQuit(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
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
    let meeting: MeetingController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if meeting.busy {
            Text("Meeting: " + meeting.state.rawValue)
            if meeting.state == .recording { Button("Pause meeting") { meeting.pause() } }
            if meeting.state == .paused { Button("Resume meeting") { meeting.resume() } }
            if meeting.state == .transcribing { Button("Cancel meeting transcription") { meeting.cancelTranscription() } }
            else { Button("Stop meeting") { meeting.stop() } }
        }
        Text(controller.state.rawValue)
        Button("Show Yada") { openWindow(id: "yada"); NSApp.activate() }
        Button(controller.state == .recording ? "Stop and finalize" : "Start recording") {
            controller.toggle(locale: language.locale)
        }.disabled(meeting.busy || language.checking || language.downloading || controller.cleaningUp || [.finalizing, .formatting, .delivering].contains(controller.state))
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
    let meeting: MeetingController
    @State private var permissions = PermissionSetup()
    @Environment(\.scenePhase) private var scenePhase
    @State private var copyStatus = ""
    @State private var showTerms = false
    @State private var showSettings = false
    private var needsSetup: Bool { (permissions.hasChecked && !permissions.ready) || (language.hasChecked && !language.installed) }
    var body: some View {
        ScrollView {
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
            HStack {
                Text("Press \(KeyboardShortcuts.getShortcut(for: .toggleDictation)?.description ?? "Control–Y") to start and stop dictation.")
                Spacer()
                Button(showSettings ? "Done" : "Settings…") { showSettings.toggle() }
            }
            if let issue = controller.shortcutIssue {
                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if needsSetup || showSettings {
            GroupBox(showSettings ? "Settings" : "Finish setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Permissions").font(.headline)
                    HStack {
                        Label(permissions.microphone == .authorized ? "Microphone ready" : "Microphone access needed", systemImage: permissions.microphone == .authorized ? "checkmark.circle" : "mic")
                        Spacer()
                        if permissions.microphone == .notDetermined {
                            Button("Allow microphone") { Task { await permissions.allowMicrophone() } }
                                .disabled(permissions.requestingMicrophone || UIValidation.isEnabled)
                        } else if permissions.microphone == .denied {
                            Button("Open microphone settings") { PermissionSetup.openSettings("Microphone") }.disabled(UIValidation.isEnabled)
                        } else if permissions.microphone == .restricted {
                            Text("Restricted by this Mac's administrator").font(.caption)
                        }
                    }
                    HStack {
                        Label(permissions.accessibility ? "Text insertion ready" : "Text insertion access needed", systemImage: permissions.accessibility ? "checkmark.circle" : "keyboard")
                        Spacer()
                        if !permissions.accessibility {
                            Button("Open Accessibility settings") { ActiveFieldInsertion.requestAccessibility() }.disabled(UIValidation.isEnabled)
                        }
                    }
                    if !permissions.accessibility {
                        Text("Enable Yada in Accessibility, then return here. We check again automatically. If it is already enabled, quit and reopen Yada; an older development build may need to be removed and added again.").font(.caption)
                    }
                    if showSettings {
                        Divider()
                        KeyboardShortcuts.Recorder("Recording shortcut", name: .toggleDictation)
                            .shortcutValidation { shortcut in
                                if shortcut.key == .function || shortcut.modifiers.contains(.function) {
                                    return .disallow(reason: "Keep Fn available for Wispr Flow.")
                                }
                                return .allow
                            }.disabled(UIValidation.isEnabled)
                        Button("Saved terminology…") { showTerms = true }
                    }
                    if let error = controller.cleanup.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    if showSettings {
                    Picker("Speech language", selection: $language.selectedID) {
                        if !language.locales.contains(where: { $0.identifier == language.selectedID }) {
                            Text(language.selectedID).tag(language.selectedID)
                        }
                        ForEach(language.locales, id: \.identifier) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                        }
                    }
                    }
                    if !language.installed || showSettings {
                    HStack {
                        Button("Check language") { Task { await language.check() } }.disabled(UIValidation.isEnabled)
                        Button("Download language") { Task { await language.download() } }
                            .disabled(language.installed || language.locales.isEmpty || UIValidation.isEnabled)
                    }
                    Text(language.status).font(.caption).fixedSize(horizontal: false, vertical: true)
                    if language.downloading { ProgressView(value: language.progress).accessibilityLabel("Language download progress") }
                    }
                }.padding(6)
            }.disabled(controller.busy || language.checking || language.downloading)
            }
            Text(controller.message).fixedSize(horizontal: false, vertical: true)
            if let error = controller.history.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if controller.state == .preparing || controller.state == .finalizing || controller.state == .formatting || controller.state == .delivering { ProgressView().controlSize(.small) }
            if controller.state == .recording {
                ProgressView(value: Double(controller.level)).tint(.red).accessibilityLabel("Microphone level")
            }
            HStack {
                Button(controller.state == .recording ? "Stop and finalize" : "Start recording") {
                    copyStatus = ""
                    controller.toggle(locale: language.locale)
                }
                .buttonStyle(.borderedProminent)
                .disabled(meeting.busy || language.checking || language.downloading || controller.cleaningUp || [.preparing, .finalizing, .formatting, .delivering].contains(controller.state))
                if controller.canCancel { Button("Cancel") { controller.cancel() }.disabled(controller.cleaningUp) }
                Spacer()
            }
            GroupBox(controller.canCopy ? "Final text" : "Preview · may change") {
                ScrollView {
                    Text(controller.canCopy ? controller.outputText : (controller.transcript.preview.isEmpty ? "Your words will appear here." : controller.transcript.preview))
                        .foregroundStyle(controller.transcript.preview.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }.frame(minHeight: 120, maxHeight: .infinity)
            }
            HStack {
                Button("Copy") {
                    copyStatus = copyLocally(controller.outputText)
                }.disabled(!controller.canCopy)
                Button("Clear") { controller.clear(); copyStatus = "" }.disabled(controller.busy)
                Text(copyStatus).font(.caption)
                Spacer()
            }
            if !controller.transcript.finalText.isEmpty && ![.preparing, .recording, .finalizing, .delivering].contains(controller.state) {
                DisclosureGroup("Original and cleanup") {
                    Text("Raw").font(.caption.bold())
                    ScrollView { Text(controller.transcript.finalText).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                    Button("Copy raw") { copyStatus = copyLocally(controller.transcript.finalText) }
                    if controller.cleanedText != controller.transcript.finalText {
                        Text("Cleaned").font(.caption.bold())
                        Text(controller.cleanedText)
                    }
                }
            }
            Text("Ordinary dictation audio is never saved. Meetings save audio until you delete it. The last 50 finalized transcripts are saved locally; manage them in Recent transcripts. Text goes directly into supported fields. Copy is available when insertion cannot be verified. Local clipboard managers may still read or sync copied text. Dictation preserves your words and tidies spacing. Your original text stays available in history.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if showSettings, let ready = controller.readinessMS {
                Text("Capture readiness: \(Int(ready)) ms" + (controller.finalizationMS.map { " · Finalization: \(Int($0)) ms" } ?? ""))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 600)
        .task { if !UIValidation.isEnabled { refreshPermissions(); await language.check() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !UIValidation.isEnabled { refreshPermissions() }
        }
        .onChange(of: controller.state) { _, _ in copyStatus = "" }
        .sheet(isPresented: $showTerms) { TerminologyView(settings: controller.cleanup) }
    }

    private func refreshPermissions() {
        permissions.refresh()
        if permissions.accessibility { controller.accessibilityGranted() }
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
    @State private var version = "Saved"
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
                    Picker("Version", selection: $version) {
                        Text("Saved").tag("Saved")
                        Text("Raw").tag("Raw")
                        if selected.cleanedText != nil { Text("Cleaned").tag("Cleaned") }
                        if selected.formattedText != nil { Text("Formatted").tag("Formatted") }
                    }.pickerStyle(.segmented)
                    ScrollView { Text(historyText(selected)).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                        .frame(minHeight: 100, maxHeight: 200)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("Copy") { copyStatus = copyLocally(historyText(selected)) }
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
        .onChange(of: selectedID) { _, _ in copyStatus = ""; version = "Saved" }
        .confirmationDialog("Delete all saved transcripts?", isPresented: $confirmClear) {
            Button("Delete all", role: .destructive) { history.clear(); selectedID = nil; copyStatus = "" }
        } message: { Text("This removes Yada's saved history. Text already copied elsewhere is unaffected.") }
    }
    private func historyText(_ entry: SavedTranscript) -> String {
        switch version {
        case "Raw": entry.rawText ?? entry.text
        case "Cleaned": entry.cleanedText ?? entry.text
        case "Formatted": entry.formattedText ?? entry.text
        default: entry.text
        }
    }

}

// A debug-only driver exercises the real views/controller without microphone or user history.
enum UIValidation {
    static var isTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
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
        return SessionController(formatter: PreviewFormatter()) { PreviewRecognition() }
    }
    #endif
    let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    return SessionController(history: RecentTranscripts(fileURL: testing ? nil : RecentTranscripts.defaultURL), cleanup: CleanupSettings(fileURL: testing ? nil : CleanupSettings.defaultURL))
}

#if DEBUG
@MainActor
private final class PreviewFormatter: TextFormatting {
    var availabilityMessage: String { "Synthetic formatter for UI checks. No model is used." }
    func format(_ text: String, style: TextMode, locale: Locale) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return style == .bullets ? "• " + text : text
    }
}

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

struct TerminologyView: View {
    let settings: CleanupSettings
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var replacement = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your terminology").font(.title2.bold())
            Text("Exact, case-sensitive phrases. Applied in Clean and reviewed modes, outside quotations and code. Raw bypasses these rules.").font(.callout)
            List(settings.replacements) { term in
                HStack {
                    Text(term.source + " → " + term.replacement)
                    Spacer()
                    Button("Delete") { settings.delete(term.source) }
                }
            }.frame(height: 180)
            TextField("Recognized phrase", text: $source)
            TextField("Replace with", text: $replacement)
            if let error = settings.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Add replacement") {
                    settings.add(source: source, replacement: replacement)
                    if settings.errorMessage == nil { source = ""; replacement = "" }
                }
                Spacer()
                Button("Done") { dismiss() }
            }
        }.padding(24).frame(width: 500)
    }
}
