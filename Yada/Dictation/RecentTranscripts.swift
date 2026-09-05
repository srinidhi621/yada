import Foundation
import Observation

struct SavedTranscript: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let text: String
}

@MainActor @Observable
final class RecentTranscripts {
    static let limit = 50
    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Yada/RecentTranscripts.json")
    }
    private(set) var entries: [SavedTranscript] = []
    private(set) var errorMessage: String?
    private var loadFailed = false
    private let fileURL: URL?

    /// A nil URL is an in-memory store for tests and UI previews.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            entries = try JSONDecoder().decode([SavedTranscript].self, from: Data(contentsOf: fileURL))
        } catch {
            loadFailed = true
            errorMessage = "Saved transcripts could not be read. Existing history has been left untouched. Clear history to start over."
        }
    }

    func append(_ text: String) {
        guard !text.isEmpty, !loadFailed else { return }
        let entry = SavedTranscript(id: UUID(), createdAt: .now, text: text)
        save(Array(([entry] + entries).prefix(Self.limit)))
    }

    func delete(id: UUID) { guard !loadFailed else { return }; save(entries.filter { $0.id != id }) }
    func clear() {
        if save([]) { loadFailed = false }
    }

    @discardableResult
    private func save(_ proposed: [SavedTranscript]) -> Bool {
        do {
            if let fileURL {
                let folder = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
                try JSONEncoder().encode(proposed).write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            entries = proposed
            errorMessage = nil
            return true
        } catch {
            errorMessage = "History could not be saved. Your current transcript is still available to copy. Check local disk access and free space."
            return false
        }
    }
}
