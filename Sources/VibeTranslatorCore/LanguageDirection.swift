import Foundation
import NaturalLanguage

/// A language the user can pick, with an optional regional variant ("en-GB", "es-419").
public struct TranslationLanguage: Codable, Hashable, Identifiable, Sendable {
    /// BCP 47 identifier.
    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    public var language: Locale.Language { Locale.Language(identifier: id) }
    public var languageCode: String { language.languageCode?.identifier ?? id }

    /// Name in the given locale, e.g. "español (España)" / "English (United Kingdom)".
    public func displayName(in locale: Locale = .autoupdatingCurrent) -> String {
        let name = locale.localizedString(forIdentifier: id) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Just the language, e.g. "Inglés", for short labels.
    public func languageName(in locale: Locale = .autoupdatingCurrent) -> String {
        let name = locale.localizedString(forLanguageCode: languageCode) ?? languageCode
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The language as it's written mid-sentence ("inglés" in Spanish, "English" in English).
    public func languageNameInSentence(in locale: Locale = .autoupdatingCurrent) -> String {
        locale.localizedString(forLanguageCode: languageCode) ?? languageCode
    }

    /// Same language regardless of the region ("es-ES" and "es-419").
    public func isSameLanguage(as other: TranslationLanguage) -> Bool {
        languageCode == other.languageCode
    }

    public static let spanishSpain = TranslationLanguage("es-ES")
    public static let englishUS = TranslationLanguage("en-US")

    /// Languages offered in Settings. LLM engines handle all of them; Apple Translation
    /// handles most, and the app says so when a pair isn't available there.
    public static let catalog: [TranslationLanguage] = [
        "es-ES", "es-419", "es-MX", "es-AR", "en-US", "en-GB", "pt-BR", "pt-PT", "fr-FR", "de-DE", "it-IT", "ca-ES",
        "nl-NL", "pl-PL", "ru-RU", "uk-UA", "tr-TR", "ar", "hi-IN", "ja-JP", "ko-KR", "zh-Hans", "zh-Hant",
    ].map(TranslationLanguage.init)
}

/// Picks the direction of a translation from the user's language and their target language.
public enum LanguageDirection {
    /// Text written in my language goes to the target; anything else comes to my language.
    public static func detect(_ text: String, native: TranslationLanguage, target: TranslationLanguage) -> (source: Locale.Language, target: Locale.Language) {
        guard let detected = dominantLanguage(of: text, hints: [native, target]) else {
            return (target.language, native.language)
        }
        if detected.languageCode?.identifier == native.languageCode {
            return (native.language, target.language)
        }
        if detected.languageCode?.identifier == target.languageCode {
            return (target.language, native.language)
        }
        return (detected, native.language)
    }

    /// On-device language identification over the prose only: mentions, links, code and
    /// emoji say nothing about the language and confuse short texts.
    static func dominantLanguage(of text: String, hints: [TranslationLanguage]) -> Locale.Language? {
        let prose = text.components(separatedBy: "\n").flatMap { line in
            DraftMarkup.segments(of: line).compactMap { if case let .text(text) = $0 { text } else { nil } }
        }.joined(separator: " ")

        // A confident guess on its own wins (a German message is German). Short or ambiguous
        // text ("vale", "ok") is decided between the user's two languages: hints make the
        // recognizer choose among them only.
        let open = NLLanguageRecognizer()
        open.processString(prose)
        if let (language, confidence) = open.languageHypotheses(withMaximum: 1).first, confidence >= 0.8 {
            return Locale.Language(identifier: language.rawValue)
        }
        let biased = NLLanguageRecognizer()
        biased.languageHints = Dictionary(hints.map { (NLLanguage($0.languageCode), 0.5) }, uniquingKeysWith: max)
        biased.processString(prose)
        guard let language = biased.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }
}
