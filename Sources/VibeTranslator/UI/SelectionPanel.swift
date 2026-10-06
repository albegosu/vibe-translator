import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SelectionPanelState {
    enum Phase {
        case translating
        case done(String)
        case failed(String)
    }

    var directionLabel = ""
    var phase = Phase.translating
    var note: String?
    var canReplace = false
    var width: CGFloat = 420
    var onCopy: () -> Void = {}
    var onReplace: () -> Void = {}
    var onClose: () -> Void = {}
}

/// Floating translation next to the cursor. It never becomes key or activates the app,
/// so the source app keeps its focus and selection (needed for "Reemplazar").
@MainActor
final class SelectionPanel {
    let state = SelectionPanelState()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    var isVisible: Bool { panel?.isVisible == true }

    func show(directionLabel: String, width: CGFloat = 420) {
        state.directionLabel = directionLabel
        state.width = width
        state.phase = .translating
        state.note = nil
        state.canReplace = false

        let panel = panel ?? makePanel()
        self.panel = panel
        let host = FirstMouseHostingView(rootView: SelectionPanelView(state: state))
        panel.contentView = host
        place(panel, size: host.fittingSize)
        panel.orderFrontRegardless()
        startDismissMonitors()
    }

    /// Re-fits the panel after the content changes, keeping its top-left corner in place.
    func refit() {
        guard let panel, let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    func close() {
        panel?.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func place(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - 16 - size.height)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if origin.y < visible.minY + 8 { origin.y = mouse.y + 16 }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func startDismissMonitors() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps or Esc close it; clicks in the panel itself never reach a global monitor.
        if let mouse = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.state.onClose() }
        }) {
            monitors.append(mouse)
        }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            MainActor.assumeIsolated { self?.state.onClose() }
        }) {
            monitors.append(keys)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.onClose() }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

/// Keyboard focus must stay in the source app, or ⌘V for "Reemplazar" would land here.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Buttons react to the first click even though the panel is never key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct SelectionPanelView: View {
    let state: SelectionPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.directionLabel).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(action: state.onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cerrar (Esc)")
            }

            switch state.phase {
            case .translating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Traduciendo…").foregroundStyle(.secondary)
                }
            case let .done(text):
                ScrollView {
                    Text(text)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: state.width > 420 ? 380 : 300)
                .fixedSize(horizontal: false, vertical: true)
                if let note = state.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if state.canReplace {
                        Button("Reemplazar", action: state.onReplace)
                    }
                    Button("Copiar", action: state.onCopy)
                        .buttonStyle(.borderedProminent)
                }
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: state.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .padding(16)
    }
}
