import AppKit
import SwiftUI

/// Small non-activating overlay for progress and results. It never steals focus
/// from Discord, so the user can keep typing right after a translation.
@MainActor
final class HUD {
    enum Style {
        case progress, success, info, error

        var symbol: String? {
            switch self {
            case .progress: nil
            case .success: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .progress, .info: .secondary
            case .success: .green
            case .error: .orange
            }
        }

        var defaultDuration: Duration? {
            switch self {
            case .progress: nil
            case .success, .info: .seconds(2)
            case .error: .seconds(5)
            }
        }
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, style: Style, duration: Duration? = nil) {
        hideTask?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(message: message, style: style))
        panel.contentView = host
        let size = host.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 48, width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()

        if let duration = duration ?? style.defaultDuration {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.panel?.orderOut(nil)
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

private struct HUDView: View {
    let message: String
    let style: HUD.Style

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = style.symbol {
                Image(systemName: symbol).foregroundStyle(style.tint).imageScale(.large)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(14)
    }
}
