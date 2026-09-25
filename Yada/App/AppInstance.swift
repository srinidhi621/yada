import AppKit
import Darwin

/// All normal Yada builds share one microphone/shortcut owner. Previews and tests opt out.
@MainActor
final class AppInstance {
    static let bundleIDs = ["com.srinidhi621.yada", "com.srinidhi621.yada.dev"]
    static let installedReleasePath = "/Applications/Yada.app"
    private var descriptor: Int32 = -1

    static func existingPID(_ candidates: [(pid: Int32, bundleID: String)], currentPID: Int32) -> Int32? {
        candidates.first { $0.pid != currentPID && bundleIDs.contains($0.bundleID) }?.pid
    }

    static func validLocation(bundleID: String?, bundleURL: URL) -> Bool {
        bundleID != bundleIDs[0] || bundleURL.standardizedFileURL.path == installedReleasePath
    }

    func acquire() throws -> Bool {
        guard Self.validLocation(bundleID: Bundle.main.bundleIdentifier, bundleURL: Bundle.main.bundleURL) else {
            throw YadaError("Move Yada.app to /Applications before opening it. Quit other Yada copies, then launch the installed app. This keeps macOS permissions tied to one location.")
        }
        let current = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications
        let candidates = applications.compactMap { app in app.bundleIdentifier.map { (pid: app.processIdentifier, bundleID: $0) } }
        if let pid = Self.existingPID(candidates, currentPID: current) {
            let existing = NSRunningApplication(processIdentifier: pid)
            existing?.activate()
            if existing?.bundleURL?.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL {
                let location = existing?.bundleURL?.path ?? "another location"
                throw YadaError("Another Yada copy is running from \(location). Quit that copy, then open /Applications/Yada.app.")
            }
            return false
        }
        let path = FileManager.default.temporaryDirectory.appending(path: "com.srinidhi621.yada.instance.lock").path
        return try acquireLock(at: URL(fileURLWithPath: path))
    }

    func acquireLock(at url: URL) throws -> Bool {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw YadaError("Could not open Yada's instance lock. Check access to the temporary folder.") }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let blocked = errno == EWOULDBLOCK
            close(descriptor); descriptor = -1
            if blocked { return false }
            throw YadaError("Could not lock Yada's instance file. Quit other copies and retry.")
        }
        return true
    }

    deinit { if descriptor >= 0 { close(descriptor) } }
}
