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

/// Floating result next to the cursor. It takes the keyboard while open (↩ runs the main
/// action, esc closes) so a stray Return never reaches the app underneath, e.g. sending a
/// chat message, but it never activates our app: the source app stays frontmost and keeps
/// its selection for "Reemplazar".
@MainActor
final class SelectionPanel {
    let state = SelectionPanelState()
    /// Gives the keyboard back to the source app when the panel closes from the keyboard
    /// or its buttons (not when the user clicked somewhere else).
    var onDismiss: (() -> Void)?
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    /// Near the bottom of the screen the panel grows upwards from its bottom edge.
    private var growsUp = false

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
        panel.makeKeyAndOrderFront(nil)
        startDismissMonitors()
    }

    /// Re-fits the panel after the content changes, keeping the edge next to the cursor in
    /// place and the whole panel on screen.
    func refit() {
        guard let panel, let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let y = growsUp ? panel.frame.minY : panel.frame.maxY - size.height
        panel.setFrame(clamped(NSRect(x: panel.frame.minX, y: y, width: size.width, height: size.height)), display: true)
    }

    func close(returnFocus: Bool = true) {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        if returnFocus { onDismiss?() }
        onDismiss = nil
    }

    private func place(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let visible = visibleFrame(at: mouse)
        // Prompt boxes usually sit at the bottom of a window: grow away from the edge.
        growsUp = mouse.y < visible.midY
        let y = growsUp ? mouse.y + 16 : mouse.y - 16 - size.height
        panel.setFrame(clamped(NSRect(x: mouse.x + 12, y: y, width: size.width, height: size.height)), display: true)
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        let visible = visibleFrame(at: NSPoint(x: frame.midX, y: frame.midY))
        var frame = frame
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        return frame
    }

    private func visibleFrame(at point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func startDismissMonitors() {
        guard monitors.isEmpty else { return }
        // A click in another app closes it (clicks in the panel never reach a global monitor);
        // that click already decides where the focus goes, so don't hand it back.
        if let mouse = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close(returnFocus: false) }
        }) {
            monitors.append(mouse)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(returnFocus: false) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

/// Borderless panels can't become key by default; this one must, to catch ↩ and esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Buttons react to the first click without a focus click first.
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
                .keyboardShortcut(.cancelAction)
                .help("Cerrar (esc)")
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
                    Text(state.canReplace ? "↩ reemplazar · esc cerrar" : "↩ copiar · esc cerrar")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if state.canReplace {
                        Button("Copiar", action: state.onCopy)
                            .keyboardShortcut("c", modifiers: .command)
                        Button("Reemplazar", action: state.onReplace)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Copiar", action: state.onCopy)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
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
