import Foundation
import Observation
import Speech

@MainActor @Observable
final class LanguageSetup {
    var locales: [Locale] = []
    var selectedID = UserDefaults.standard.string(forKey: "speechLocale") ?? "en-IN" {
        didSet {
            guard oldValue != selectedID else { return }
            installed = false
            status = "Check this language before recording."
        }
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
        defer { checking = false }
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
        UserDefaults.standard.set(selectedID, forKey: "speechLocale")
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        installed = await AssetInventory.status(forModules: [transcriber]) == .installed
        status = installed ? "Language installed. Recognition is ready for offline use." : "Language assets are missing. Download once before recording."
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
            let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
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
            status = "Language download failed. Check the connection and retry. No recording has started."
        }
    }
}
