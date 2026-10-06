import Foundation

/// Text helpers shared by the translator and the "is it still the same draft?" checks.
public enum DraftText {
    private static let invisibles: Set<Character> = ["\u{200B}", "\u{200C}", "\u{2060}", "\u{FEFF}"]

    /// Canonical form for comparing what we read from an editor at different moments.
    /// Editors may hand back NBSPs, zero-width characters, CRLF or a trailing newline
    /// for text that is, for the user, identical.
    public static func normalized(_ text: String) -> String {
        String(text.filter { !invisibles.contains($0) }.map { equivalents[$0] ?? $0 })
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Substitutions editors make on their own (smart quotes, line separators, NBSP).
    private static let equivalents: [Character: Character] = [
        "\u{00A0}": " ", "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
        "\u{2028}": "\n", "\u{2029}": "\n", "\r": "\n",
    ]

    public static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    public static func hasLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isAlphabetic }
    }

    /// Makes the first letter of `translation` follow the case of the first letter of `source`
    /// ("tío, …" → "dude, …", "¿Hacemos…?" → "Do we…?"). Engines don't reliably do this.
    /// Leaves lines that start with markup alone and never lowercases the pronoun "I".
    public static func mirroringLeadingCase(of source: String, in translation: String) -> String {
        guard let sourceIndex = leadingLetterIndex(in: source),
              let index = leadingLetterIndex(in: translation) else { return translation }
        let letter = translation[index]
        let wantsUppercase = source[sourceIndex].isUppercase
        guard letter.isUppercase || letter.isLowercase, letter.isUppercase != wantsUppercase else { return translation }
        if !wantsUppercase, isPronounI(translation, at: index) { return translation }
        let replacement = wantsUppercase ? letter.uppercased() : letter.lowercased()
        return translation.replacingCharacters(in: index...index, with: replacement)
    }

    private static let openingMarks: Set<Character> = ["¿", "¡", "\"", "'", "“", "‘", "(", "["]

    private static func leadingLetterIndex(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex, openingMarks.contains(text[index]) {
            index = text.index(after: index)
        }
        return index < text.endIndex && text[index].isLetter ? index : nil
    }

    private static func isPronounI(_ text: String, at index: String.Index) -> Bool {
        guard text[index] == "I" else { return false }
        let next = text.index(after: index)
        return next == text.endIndex || !text[next].isLetter
    }
}
