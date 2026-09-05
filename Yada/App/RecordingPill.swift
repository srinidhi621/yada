import AppKit
import SwiftUI

/// A non-activating panel keeps the foreground application's keyboard focus.
final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingPill {
    private(set) var panel: RecordingPanel?

    func update(controller: SessionController) {
        guard [.preparing, .recording, .finalizing, .delivering].contains(controller.state) else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil {
            let panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 44),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Yada recording controls"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: RecordingPillView(controller: controller))
            self.panel = panel
            placeOnActiveScreen(panel)
        } else if let panel, !panel.isVisible {
            // Keep a user's dragged position while its screen is connected.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
                placeOnActiveScreen(panel)
            }
        }
        panel?.orderFrontRegardless()
    }

    private func placeOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        // Bottom-right leaves the usual bottom-center dictation pill free.
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.minY + 28))
    }
}

struct RecordingPillView: View {
    let controller: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [0.35, 0.65, 1, 0.55, 0.85, 0.45, 0.7]

    var body: some View {
        HStack(spacing: 10) {
            if controller.state == .recording {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(heights.indices, id: \.self) { index in
                        Capsule().fill(.teal)
                            .frame(width: 2, height: 3 + CGFloat(controller.level) * heights[index] * 19)
                    }
                }
                .frame(width: 28, height: 24)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: controller.level)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Microphone input level")
                .accessibilityValue("\(Int(controller.level * 100)) percent")
            } else {
                ProgressView().controlSize(.small).frame(width: 28, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Yada").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(controller.state == .recording ? "Listening" : controller.state.rawValue)
                    .font(.system(size: 11, weight: .semibold))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if controller.state == .recording {
                Button { controller.stop() } label: { Image(systemName: "stop.fill") }
                    .help("Stop and finalize").accessibilityLabel("Stop and finalize")
            }
            if controller.canCancel {
                Button { controller.cancel() } label: { Image(systemName: "xmark") }
                    .help("Cancel recording").accessibilityLabel("Cancel recording")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(width: 230, height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
