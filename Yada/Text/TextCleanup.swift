import Foundation
import Observation

enum TextMode: String, Codable, CaseIterable, Identifiable {
    case raw = "Raw", clean = "Clean", prose = "Prose", bullets = "Bullets", email = "Email"
    var id: String { rawValue }
    var requiresReview: Bool { ![.raw, .clean].contains(self) }
}

struct TermReplacement: Codable, Equatable, Identifiable {
    var id: String { source }
    let source: String
    let replacement: String
}

@MainActor @Observable
final class CleanupSettings {
    static var defaultURL: URL { AppStorage.directory.appending(path: "CleanupSettings.json") }
    private(set) var mode: TextMode = .raw
    private(set) var replacements: [TermReplacement] = []
    private(set) var errorMessage: String?
    private var loadFailed = false
    private let fileURL: URL?
    private struct Stored: Codable { let mode: TextMode; let replacements: [TermReplacement] }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))
            guard saved.replacements.count <= 100,
                  Set(saved.replacements.map(\.source)).count == saved.replacements.count,
                  saved.replacements.allSatisfy({ Self.valid($0) }) else { throw YadaError("Invalid replacements") }
            mode = saved.mode
            replacements = saved.replacements
        } catch {
            loadFailed = true
            errorMessage = "Cleanup settings could not be read. Raw mode is active; the existing file has been left untouched."
        }
    }
    private static func valid(_ term: TermReplacement) -> Bool {
        !term.source.isEmpty && !term.replacement.isEmpty && term.source.count <= 120 && term.replacement.count <= 240 &&
        !term.source.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
        !term.replacement.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    func setMode(_ mode: TextMode) { save(mode: mode, replacements: replacements) }
    func add(source: String, replacement: String) {
        let term = TermReplacement(source: source.trimmingCharacters(in: .whitespacesAndNewlines), replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines))
        guard Self.valid(term), replacements.count < 100, !replacements.contains(where: { $0.source == term.source }) else {
            errorMessage = "Use a unique, nonempty phrase (up to 120 characters) and replacement (up to 240), without line breaks. Maximum 100 phrases."
            return
        }
        save(mode: mode, replacements: replacements + [term])
    }
    func delete(_ source: String) { save(mode: mode, replacements: replacements.filter { $0.source != source }) }
    private func save(mode: TextMode, replacements: [TermReplacement]) {
        guard !loadFailed else { return }
        do {
            if let fileURL {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try JSONEncoder().encode(Stored(mode: mode, replacements: replacements)).write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            self.mode = mode; self.replacements = replacements; errorMessage = nil
        } catch { errorMessage = "Cleanup settings could not be saved. The previous settings are still active." }
    }
}

enum TextCleanup {
    static let version = "whitespace-terms-v2"

    // Immutable syntax rule compiled once. Dynamic terminology is compiled once per utterance.
    private static let protected = try! NSRegularExpression(pattern: #"```[\s\S]*?(?:```|$)|`[^`\n]*`|"[^"\n]*"|“[^”\n]*”|(?<![\p{L}\p{N}])'[^'\n]*'|(?m:^\h{2,}[^\n]*$)|(?m:^\t[^\n]*$)"#)

    static func apply(_ raw: String, replacements: [TermReplacement]) -> String {
        let lookup = Dictionary(uniqueKeysWithValues: replacements.map { ($0.source, $0.replacement) })
        let alternatives = replacements.map(\.source).sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let terms = replacements.isEmpty ? nil : try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{M}\\p{N}_])(?:" + alternatives + ")(?![\\p{L}\\p{M}\\p{N}_])")

        func clean(_ text: String) -> String {
            let normalized = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            guard let terms else { return normalized }
            let original = normalized as NSString
            let result = NSMutableString(string: normalized)
            // Match the original once: replacements never trigger other replacements.
            for match in terms.matches(in: normalized, range: NSRange(location: 0, length: original.length)).reversed() {
                result.replaceCharacters(in: match.range, with: lookup[original.substring(with: match.range)]!)
            }
            return result as String
        }

        // Preserve explicit quotations and code; no filler words are deleted by rules.
        let source = raw as NSString
        var cursor = 0
        var output = ""
        for match in protected.matches(in: raw, range: NSRange(location: 0, length: source.length)) {
            output += clean(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            output += source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        output += clean(source.substring(from: cursor))
        return output
    }
}
