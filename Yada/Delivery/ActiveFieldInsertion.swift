import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CryptoKit

@MainActor
protocol InsertionTarget: AnyObject {
    func insert(_ text: String) async -> InsertionResult
}

enum InsertionResult: Equatable {
    case inserted
    case notInserted(String)
    case uncertain(String)
}

@MainActor
enum InsertionPreparation {
    case preview(String?)
    case target(any InsertionTarget)
    case needsAccessibility
}

/// A text fingerprint and UTF-16 selection guard; never persisted or logged.
struct FieldSnapshot: Equatable {
    let digest: Data
    let selection: NSRange

    init?(text: String, selection: NSRange) {
        let length = (text as NSString).length
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= length, selection.length <= length - selection.location else { return nil }
        digest = Data(SHA256.hash(data: Data(text.utf8)))
        self.selection = selection
    }

    func expectedText(before: String, inserting text: String) -> String? {
        guard FieldSnapshot(text: before, selection: selection) == self else { return nil }
        return (before as NSString).replacingCharacters(in: selection, with: text)
    }
}

enum FieldDelivery: Equatable {
    case selectedText, paste

    static func choose(bundleID: String, selectedTextSettable: Bool) -> FieldDelivery? {
        // Web-backed Office editors need a paste event to update their document model.
        if ["com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams"].contains(bundleID) {
            return .paste
        }
        return selectedTextSettable ? .selectedText : nil
    }
}

@MainActor
final class ActiveFieldInsertion: InsertionTarget {
    private let pid: pid_t
    private let element: AXUIElement
    private let snapshot: FieldSnapshot
    private let delivery: FieldDelivery
    private let bundleID: String
    private var activationObserver: NSObjectProtocol?
    private var leftApplication = false
    private var attempted = false

    private init(pid: pid_t, bundleID: String, element: AXUIElement, snapshot: FieldSnapshot, delivery: FieldDelivery) {
        self.pid = pid
        self.bundleID = bundleID
        self.delivery = delivery
        self.element = element
        self.snapshot = snapshot
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let activatedPID, activatedPID != self?.pid { self?.leftApplication = true }
            }
        }
    }

    isolated deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    static func capture() -> InsertionPreparation {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return .preview(nil) }
        let terminalApps: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "dev.warp.Warp", "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper", "org.tabby"]
        guard !terminalApps.contains(bundleID) else {
            return .preview("Terminal dictation stays in preview. Copy only after reviewing it.")
        }
        guard !IsSecureEventInputEnabled() else { return .preview("Secure keyboard input is active. Use the preview to copy your text.") }
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        guard let element = focusedElement(appElement),
              let delivery = deliveryMethod(element, bundleID: bundleID),
              let text = stringAttribute(element, kAXValueAttribute),
              let selection = selectedRange(element),
              let snapshot = FieldSnapshot(text: text, selection: selection) else {
            return .preview("This field does not expose enough information for reliable insertion. Your transcript will be available here to copy.")
        }
        AXUIElementSetMessagingTimeout(element, 0.3)
        return .target(ActiveFieldInsertion(pid: app.processIdentifier, bundleID: bundleID, element: element, snapshot: snapshot, delivery: delivery))
    }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func unchangedField() -> String? {
        guard !leftApplication, !IsSecureEventInputEnabled(), AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let focused = Self.focusedElement(app), CFEqual(focused, element), Self.deliveryMethod(element, bundleID: bundleID) == delivery,
              let selection = Self.selectedRange(element),
              let text = Self.stringAttribute(element, kAXValueAttribute),
              FieldSnapshot(text: text, selection: selection) == snapshot else { return nil }
        return text
    }

    func insert(_ text: String) async -> InsertionResult {
        guard !attempted else { return .uncertain("Insertion was already attempted. Check the destination before copying again.") }
        attempted = true
        guard !text.isEmpty else { return .notInserted("No speech was finalized.") }
        guard !Task.isCancelled, let before = unchangedField(),
              let expected = snapshot.expectedText(before: before, inserting: text) else {
            return .notInserted("The active application, document, text or cursor changed. Your transcript is here to copy.")
        }
        // Recheck immediately before delivery; never assign the whole field value.
        guard unchangedField() != nil else {
            return .notInserted("The field changed before insertion. Your transcript is here to copy.")
        }
        switch delivery {
        case .selectedText:
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            guard result == .success else {
                return .uncertain("macOS could not confirm the insertion. Check the destination before copying again. Yada will not retry automatically.")
            }
        case .paste:
            // Construct both events before touching the clipboard. Never send Return.
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                return .notInserted("Could not prepare insertion. Your transcript is here to copy.")
            }
            let clipboard = NSPasteboard.general
            clipboard.prepareForNewContents(with: .currentHostOnly)
            guard clipboard.setString(text, forType: .string) else {
                return .notInserted("Could not prepare the clipboard. Your transcript is here to copy.")
            }
            let ownedChange = clipboard.changeCount
            guard unchangedField() != nil, clipboard.changeCount == ownedChange else {
                return .notInserted("The destination or clipboard changed. Your transcript is here to copy.")
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.postToPid(pid)
            up.postToPid(pid)
            // Leave the transcript on the clipboard: restoring it on a timer can race
            // the editor's asynchronous paste. Never retry an unacknowledged paste.
        }
        for _ in 0..<10 {
            if Self.stringAttribute(element, kAXValueAttribute) == expected { return .inserted }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return .uncertain("Insertion was requested, but could not be verified. Check the destination before copying again. Yada will not retry automatically.")
    }

    private static func deliveryMethod(_ element: AXUIElement, bundleID: String) -> FieldDelivery? {
        guard let role = stringAttribute(element, kAXRoleAttribute),
              [kAXTextAreaRole, kAXTextFieldRole].contains(role),
              stringAttribute(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole,
              attribute(element, kAXEnabledAttribute) as? Bool != false else { return nil }
        var settable = DarwinBoolean(false)
        let writable = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
        return FieldDelivery.choose(bundleID: bundleID, selectedTextSettable: writable)
    }

    private static func focusedElement(_ app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
