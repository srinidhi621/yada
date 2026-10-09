import Foundation

// Development builds never open the everyday app's saved history or cleanup settings.
enum AppStorage {
    static var directory: URL {
        let name = Bundle.main.bundleIdentifier == "com.srinidhi621.yada.dev" ? "Yada Development" : "Yada"
        #if os(macOS)
        return URL.applicationSupportDirectory.appending(path: name)
        #else
        // The Mac app never takes this branch. It exists so portable logic tests can compile off macOS.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appending(path: name)
        #endif
    }
}
