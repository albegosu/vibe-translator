import Foundation

public struct AllowedApp: Codable, Hashable, Identifiable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public var id: String { bundleID }
}

public enum AppScopeMode: String, Codable, CaseIterable, Sendable {
    case allApps
    case selectedApps
}

/// Where "translate draft" may act. Any app by default; optionally only a chosen list.
/// Terminals are always excluded: ⌘A grabs the whole scrollback and pasting several lines
/// into a shell runs them as commands.
public struct AppScope: Codable, Equatable, Sendable {
    public var mode: AppScopeMode
    public var apps: [AllowedApp]

    public init(mode: AppScopeMode = .allApps, apps: [AllowedApp] = []) {
        self.mode = mode
        self.apps = apps
    }

    public func allows(_ bundleID: String?) -> Bool {
        switch mode {
        case .allApps: true
        case .selectedApps: bundleID.map { id in apps.contains { $0.bundleID == id } } ?? false
        }
    }

    public static func isTerminal(_ bundleID: String?) -> Bool {
        bundleID.map(terminalBundleIDs.contains) ?? false
    }

    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
    ]

    public static let discordApps: [AllowedApp] = [
        AllowedApp(bundleID: "com.hnc.Discord", name: "Discord"),
        AllowedApp(bundleID: "com.hnc.DiscordPTB", name: "Discord PTB"),
        AllowedApp(bundleID: "com.hnc.DiscordCanary", name: "Discord Canary"),
    ]

    /// v0.1–0.2 only had "translate drafts only in Discord" (on unless turned off).
    /// Someone who saved it turned on keeps that behaviour as a Discord-only list;
    /// everyone else starts with all apps.
    public static func migrated(onlyInDiscord: Bool?) -> AppScope {
        onlyInDiscord == true ? AppScope(mode: .selectedApps, apps: discordApps) : AppScope()
    }
}
