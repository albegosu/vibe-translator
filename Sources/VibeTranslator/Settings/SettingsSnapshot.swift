import AppKit
import SwiftUI

/// Developer tool: `VibeTranslator --render-settings <folder>` writes every settings tab
/// as PNG, in light and dark appearance, then quits. Useful to review the layout and for
/// README screenshots without clicking through the app.
@MainActor
enum SettingsSnapshot {
    static func renderIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-settings"), index + 1 < arguments.count else { return false }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let model = AppModel.shared
        let tabs: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsTab(model: model))),
            ("traduccion", AnyView(TranslationSettingsTab(model: model))),
            ("prompts", AnyView(PromptSettingsTab(model: model))),
        ]
        for (name, view) in tabs {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                render(view, appearance: appearance, to: folder.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        return true
    }

    private static func render(_ view: AnyView, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
