import Testing
@testable import VibeTranslatorCore

struct AppScopeTests {
    @Test func allAppsByDefault() {
        let scope = AppScope()
        #expect(scope.allows("com.tinyspeck.slackmacgap"))
        #expect(scope.allows("com.hnc.Discord"))
        #expect(scope.allows(nil))
    }

    @Test func selectedAppsOnly() {
        let scope = AppScope(mode: .selectedApps, apps: [AllowedApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")])
        #expect(scope.allows("com.tinyspeck.slackmacgap"))
        #expect(!scope.allows("com.hnc.Discord"))
        #expect(!scope.allows(nil))
    }

    @Test func emptySelectionAllowsNothing() {
        #expect(!AppScope(mode: .selectedApps, apps: []).allows("com.hnc.Discord"))
    }

    @Test func recognisesTerminals() {
        #expect(AppScope.isTerminal("com.apple.Terminal"))
        #expect(AppScope.isTerminal("com.googlecode.iterm2"))
        #expect(!AppScope.isTerminal("com.hnc.Discord"))
        #expect(!AppScope.isTerminal(nil))
    }

    @Test func migratesTheOldDiscordSetting() {
        #expect(AppScope.migrated(onlyInDiscord: true) == AppScope(mode: .selectedApps, apps: AppScope.discordApps))
        #expect(AppScope.migrated(onlyInDiscord: false) == AppScope())
        #expect(AppScope.migrated(onlyInDiscord: nil) == AppScope())
    }
}
