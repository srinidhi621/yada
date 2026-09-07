import AppKit
import AVFoundation
import ApplicationServices
import Observation

@MainActor @Observable
final class PermissionSetup {
    private(set) var hasChecked = false
    var ready: Bool { accessibility && microphone == .authorized }
    private(set) var accessibility = false
    private(set) var microphone: AVAuthorizationStatus = .notDetermined
    private(set) var requestingMicrophone = false
    private let readAccessibility: () -> Bool
    private let readMicrophone: () -> AVAuthorizationStatus
    private let requestMicrophone: () async -> Bool

    init(readAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
         readMicrophone: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
         requestMicrophone: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }) {
        self.readAccessibility = readAccessibility
        self.readMicrophone = readMicrophone
        self.requestMicrophone = requestMicrophone
    }

    func refresh() {
        accessibility = readAccessibility()
        microphone = readMicrophone()
        hasChecked = true
    }

    func allowMicrophone() async {
        guard !requestingMicrophone else { return }
        refresh()
        guard microphone == .notDetermined else { return }
        requestingMicrophone = true
        _ = await requestMicrophone()
        refresh()
        requestingMicrophone = false
    }

    static func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) else { return }
        NSWorkspace.shared.open(url)
    }
}

// Development builds never open the everyday app's saved history or cleanup settings.
enum AppStorage {
    static var directory: URL {
        let name = Bundle.main.bundleIdentifier == "com.srinidhi621.yada.dev" ? "Yada Development" : "Yada"
        return URL.applicationSupportDirectory.appending(path: name)
    }
}
