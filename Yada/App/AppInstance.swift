import AppKit
import Darwin

/// All normal Yada builds share one microphone/shortcut owner. Previews and tests opt out.
@MainActor
final class AppInstance {
    static let bundleIDs = ["com.srinidhi621.yada", "com.srinidhi621.yada.dev"]
    private var descriptor: Int32 = -1

    static func existingPID(_ candidates: [(pid: Int32, bundleID: String)], currentPID: Int32) -> Int32? {
        candidates.first { $0.pid != currentPID && bundleIDs.contains($0.bundleID) }?.pid
    }

    func acquire() throws -> Bool {
        let current = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications
        let candidates = applications.compactMap { app in app.bundleIdentifier.map { (pid: app.processIdentifier, bundleID: $0) } }
        if let pid = Self.existingPID(candidates, currentPID: current) {
            NSRunningApplication(processIdentifier: pid)?.activate()
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
