import Foundation
import Observation
import Speech

@MainActor @Observable
final class LanguageSetup {
    private let defaults: UserDefaults
    private(set) var hasChecked = false
    var locales: [Locale] = []
    var selectedID: String {
        didSet {
            guard oldValue != selectedID else { return }
            defaults.set(selectedID, forKey: "speechLocale")
            installed = false
            status = "Check this language before recording."
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedID = defaults.string(forKey: "speechLocale") ?? "en-IN"
    }
    var status = "Check language availability before recording."
    var installed = false
    var checking = false
    var downloading = false
    var progress: Double = 0
    var locale: Locale { Locale(identifier: selectedID) }

    func check() async {
        guard !checking, !downloading else { return }
        checking = true
        installed = false
        status = "Checking speech language readiness…"
        defer { checking = false; hasChecked = true }
        guard SpeechTranscriber.isAvailable else {
            status = "Apple on-device transcription is unavailable on this Mac."
            return
        }
        locales = await SpeechTranscriber.supportedLocales.sorted { $0.identifier < $1.identifier }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            status = "Select a supported speech language."
            return
        }
        selectedID = supported.identifier
        defaults.set(selectedID, forKey: "speechLocale")
        let transcriber = AppleSpeechSession.transcriber(locale: supported)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            installed = true
            status = "Language installed. Recognition is ready for offline use."
        case .downloading:
            status = "Apple is still downloading this speech language. Check again in a moment."
        case .supported:
            status = "Language assets are missing. Download once before recording."
        case .unsupported:
            status = "This speech language is unavailable for the current recognizer. Choose another language."
        @unknown default:
            status = "Could not determine speech language readiness. Check again."
        }
    }

    func download() async {
        guard !downloading, !checking else { return }
        downloading = true
        installed = false
        progress = 0
        status = "Preparing language download. No microphone audio is captured."
        do {
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw YadaError("Choose a supported language before downloading.")
            }
            let transcriber = AppleSpeechSession.transcriber(locale: supported)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let progressTask = Task {
                    while !Task.isCancelled {
                        progress = request.progress.fractionCompleted
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { progressTask.cancel() }
                status = "Downloading speech language from Apple…"
                try await request.downloadAndInstall()
            }
            downloading = false
            await check()
        } catch {
            downloading = false
            let reason = (error as? YadaError)?.message ?? error.localizedDescription
            status = "Language download failed: \(reason). No recording has started."
        }
    }
}
