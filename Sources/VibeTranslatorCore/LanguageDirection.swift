import Foundation
import NaturalLanguage

/// Picks the direction for "translate selection": Spanish goes to English, anything else
/// (English in practice) comes to Spanish.
public enum LanguageDirection {
    public static let spanish = Locale.Language(identifier: "es")
    public static let english = Locale.Language(identifier: "en")

    public static func detect(_ text: String) -> (source: Locale.Language, target: Locale.Language) {
        let source = dominantLanguage(of: text) ?? english
        return source.languageCode?.identifier == "es" ? (source, english) : (source, spanish)
    }

    /// On-device language identification over the prose only: mentions, links, code and
    /// emoji say nothing about the language and confuse short texts.
    static func dominantLanguage(of text: String) -> Locale.Language? {
        let prose = text.components(separatedBy: "\n").flatMap { line in
            DraftMarkup.segments(of: line).compactMap { if case let .text(text) = $0 { text } else { nil } }
        }.joined(separator: " ")

        let recognizer = NLLanguageRecognizer()
        // Bias towards the two languages this app is about, without excluding others.
        recognizer.languageHints = [.spanish: 0.4, .english: 0.4]
        recognizer.processString(prose)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }
}
