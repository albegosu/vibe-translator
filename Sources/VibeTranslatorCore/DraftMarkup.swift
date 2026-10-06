import Foundation

/// A piece of a draft line: prose to translate, or markup that must survive verbatim.
public enum DraftSegment: Equatable, Sendable {
    case text(String)
    case protected(String)
}

/// Discord markup recognition. Everything matched here is kept byte-for-byte.
public enum DraftMarkup {
    /// Fenced code blocks (an unclosed fence protects the rest of the draft, as Discord would render it).
    static let codeFence = regex("```[\\s\\S]*?(?:```|\\z)")

    /// Block-level line prefixes: quotes, headings, subtext, bullet and numbered lists.
    static let blockPrefix = regex(#"^[ \t]*(?:(?:>>>|>|#{1,3}|-#|[-*+]|\d{1,3}[.)])[ \t]+)*"#)

    static let trailingWhitespace = regex(#"[ \t\r]*\z"#)

    /// Inline markup, in priority order (leftmost alternative wins at the same position).
    static let inline = regex([
        #"``(?:[^`]|`(?!`))+``|`[^`]+`"#,                     // inline code (double backticks may wrap single ones)
        #"<a?:\w{2,32}:\d{5,}>"#,                            // custom emoji
        #"<(?:@[!&]?|#)\d{5,}>"#,                            // user / role / channel mentions
        #"</[^>\n]+:\d{5,}>"#,                               // slash command mentions
        #"<t:-?\d+(?::[tTdDfFR])?>"#,                        // timestamps
        #"<id:\w+>"#,                                        // guild navigation
        #"\[[^\]\n]+\]\(<?https?://[^\s)>]+>?\)"#,           // masked links
        #"<https?://[^\s>]+>"#,                              // links with embeds suppressed
        #"https?://[^\s<]*[^\s<.,:;"'!?)\]]"#,               // bare links (no trailing punctuation)
        #"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#,                    // e-mail addresses
        #"(?<![\w@])@(?:everyone|here|[\p{L}\p{N}_](?:[\p{L}\p{N}_.]{0,30}[\p{L}\p{N}_])?)"#, // @mentions as typed
        #"(?<![\w#&])#[\p{L}\p{N}_-]+"#,                      // #channel mentions as typed
        #":(?=[\w+-]*[A-Za-z])[\w+-]{2,}:"#,                 // :emoji_shortcodes:
        #"[\x{1F1E6}-\x{1F1FF}]{2}"#,                         // flag emoji
        #"[0-9#*]\x{FE0F}?\x{20E3}"#,                        // keycap emoji
        #"\p{Extended_Pictographic}[\x{FE0F}\x{1F3FB}-\x{1F3FF}]*(?:\x{200D}\p{Extended_Pictographic}[\x{FE0F}\x{1F3FB}-\x{1F3FF}]*)*"#, // emoji
        #"\*\*|__|~~|\|\||\*|(?<!\w)_|_(?!\w)"#,             // formatting markers
    ].joined(separator: "|"))

    /// Splits a single line of prose into translatable text and protected markup.
    /// Adjacent protected pieces are merged so the engine sees as few placeholders as possible.
    public static func segments(of line: String) -> [DraftSegment] {
        let ns = line as NSString
        var result: [DraftSegment] = []
        var cursor = 0

        func append(_ segment: DraftSegment) {
            if case let .protected(new) = segment, case let .protected(previous)? = result.last {
                result[result.count - 1] = .protected(previous + new)
            } else {
                result.append(segment)
            }
        }

        for match in inline.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            append(.protected(ns.substring(with: match.range)))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length {
            append(.text(ns.substring(from: cursor)))
        }
        return result
    }

    static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid built-in pattern \(pattern): \(error)")
        }
    }
}
