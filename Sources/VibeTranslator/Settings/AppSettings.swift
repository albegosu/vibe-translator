import Foundation
import Observation
import VibeTranslatorCore

enum EngineKind: String, CaseIterable, Identifiable {
    case appleIntelligence
    case ollama
    case appleTranslation = "apple"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: String(localized: "Apple Intelligence (LLM en el Mac)")
        case .ollama: "Ollama (LLM)"
        case .appleTranslation: String(localized: "Apple Translation (traducción automática)")
        }
    }

    /// LLM engines follow the style profile; plain machine translation can't.
    var usesStyle: Bool { self != .appleTranslation }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    /// Called when a shortcut changes so hot keys can be re-registered.
    @ObservationIgnored var onShortcutsChanged: (() -> Void)?

    var translateShortcut: Shortcut? {
        didSet { save(translateShortcut, Keys.translateShortcut); onShortcutsChanged?() }
    }

    var restoreShortcut: Shortcut? {
        didSet { save(restoreShortcut, Keys.restoreShortcut); onShortcutsChanged?() }
    }

    var selectionShortcut: Shortcut? {
        didSet { save(selectionShortcut, Keys.selectionShortcut); onShortcutsChanged?() }
    }

    var promptShortcut: Shortcut? {
        didSet { save(promptShortcut, Keys.promptShortcut); onShortcutsChanged?() }
    }

    var promptProfile: PromptProfile {
        didSet { defaults.set(promptProfile.rawValue, forKey: Keys.promptProfile) }
    }

    var promptToEnglish: Bool {
        didSet { defaults.set(promptToEnglish, forKey: Keys.promptToEnglish) }
    }

    var accessMode: AccessMode {
        didSet { defaults.set(accessMode.rawValue, forKey: Keys.accessMode) }
    }

    var engine: EngineKind {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// The language I write in, and the one drafts are translated into.
    var nativeLanguage: TranslationLanguage {
        didSet { defaults.set(nativeLanguage.id, forKey: Keys.nativeLanguage); onLanguagesChanged?() }
    }

    var targetLanguage: TranslationLanguage {
        didSet { defaults.set(targetLanguage.id, forKey: Keys.targetLanguage); onLanguagesChanged?() }
    }

    @ObservationIgnored var onLanguagesChanged: (() -> Void)?

    var languagesAreValid: Bool { !nativeLanguage.isSameLanguage(as: targetLanguage) }

    /// Apps where "translate draft" may act (all of them unless the user picks some).
    var appScope: AppScope {
        didSet { defaults.set(try? JSONEncoder().encode(appScope), forKey: Keys.appScope) }
    }

    var tone: TranslationTone {
        didSet { defaults.set(tone.rawValue, forKey: Keys.tone) }
    }

    /// Terms kept verbatim, comma or newline separated.
    var glossaryText: String {
        didSet { defaults.set(glossaryText, forKey: Keys.glossary) }
    }

    var extraInstructions: String {
        didSet { defaults.set(extraInstructions, forKey: Keys.extraInstructions) }
    }

    var ollamaURL: String {
        didSet { defaults.set(ollamaURL, forKey: Keys.ollamaURL) }
    }

    var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    var style: TranslationStyle {
        TranslationStyle(tone: tone, glossary: TranslationStyle.glossary(from: glossaryText), extraInstructions: extraInstructions)
    }

    var ollamaBaseURL: URL {
        URL(string: ollamaURL.trimmingCharacters(in: .whitespaces)) ?? URL(string: Self.defaultOllamaURL)!
    }

    static let defaultOllamaURL = "http://localhost:11434"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        translateShortcut = Self.load(Keys.translateShortcut, defaults) ?? .defaultTranslate
        restoreShortcut = Self.load(Keys.restoreShortcut, defaults) ?? .defaultRestore
        selectionShortcut = Self.load(Keys.selectionShortcut, defaults) ?? .defaultSelection
        promptShortcut = Self.load(Keys.promptShortcut, defaults) ?? .defaultPrompt
        promptProfile = defaults.string(forKey: Keys.promptProfile).flatMap(PromptProfile.init(rawValue:)) ?? .agentTask
        promptToEnglish = defaults.object(forKey: Keys.promptToEnglish) as? Bool ?? true
        accessMode = defaults.string(forKey: Keys.accessMode).flatMap(AccessMode.init(rawValue:)) ?? .automatic
        engine = defaults.string(forKey: Keys.engine).flatMap(EngineKind.init(rawValue:)) ?? .appleIntelligence
        nativeLanguage = defaults.string(forKey: Keys.nativeLanguage).map(TranslationLanguage.init) ?? .spanishSpain
        targetLanguage = defaults.string(forKey: Keys.targetLanguage).map(TranslationLanguage.init) ?? .englishUS
        appScope = defaults.data(forKey: Keys.appScope).flatMap { try? JSONDecoder().decode(AppScope.self, from: $0) }
            ?? AppScope.migrated(onlyInDiscord: defaults.object(forKey: Keys.legacyOnlyInDiscord) as? Bool)
        tone = defaults.string(forKey: Keys.tone).flatMap(TranslationTone.init(rawValue:)) ?? .relaxedTechnical
        glossaryText = defaults.string(forKey: Keys.glossary) ?? ""
        extraInstructions = defaults.string(forKey: Keys.extraInstructions) ?? ""
        ollamaURL = defaults.string(forKey: Keys.ollamaURL) ?? Self.defaultOllamaURL
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? ""
    }

    // A cleared shortcut is stored as an explicit "none" so it doesn't come back as the default.
    private func save(_ shortcut: Shortcut?, _ key: String) {
        defaults.set(try? JSONEncoder().encode(StoredShortcut(shortcut: shortcut)), forKey: key)
    }

    private static func load(_ key: String, _ defaults: UserDefaults) -> Shortcut?? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data) else { return nil }
        return .some(stored.shortcut)
    }

    private struct StoredShortcut: Codable {
        var shortcut: Shortcut?
    }

    private enum Keys {
        static let translateShortcut = "translateShortcut"
        static let restoreShortcut = "restoreShortcut"
        static let selectionShortcut = "selectionShortcut"
        static let promptShortcut = "promptShortcut"
        static let promptProfile = "promptProfile"
        static let promptToEnglish = "promptToEnglish"
        static let accessMode = "accessMode"
        static let engine = "engine"
        static let appScope = "appScope"
        static let nativeLanguage = "nativeLanguage"
        static let targetLanguage = "targetLanguage"
        static let legacyOnlyInDiscord = "onlyInDiscord"
        static let tone = "tone"
        static let glossary = "glossary"
        static let extraInstructions = "extraInstructions"
        static let ollamaURL = "ollamaURL"
        static let ollamaModel = "ollamaModel"
    }
}
