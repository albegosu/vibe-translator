import Testing
@testable import VibeTranslatorCore

struct DraftMarkupTests {
    private func protectedSpans(_ line: String) -> [String] {
        DraftMarkup.segments(of: line).compactMap { if case let .protected(span) = $0 { span } else { nil } }
    }

    @Test(arguments: [
        ("hola <@123456789012345678> qué tal", "<@123456789012345678>"),
        ("hola <@!123456789012345678>", "<@!123456789012345678>"),
        ("aviso a <@&123456789012345678>", "<@&123456789012345678>"),
        ("mira <#123456789012345678>", "<#123456789012345678>"),
        ("qué risa <:kekw:123456789012345678>", "<:kekw:123456789012345678>"),
        ("baila <a:party:123456789012345678>", "<a:party:123456789012345678>"),
        ("a las <t:1700000000:R> nos vemos", "<t:1700000000:R>"),
        ("usa </deploy prod:123456789012345678>", "</deploy prod:123456789012345678>"),
        ("hola @juan.perez qué tal", "@juan.perez"),
        ("atención @everyone", "@everyone"),
        ("en #general-dev", "#general-dev"),
        ("me encanta :thumbsup:", ":thumbsup:"),
        ("genial 👍🏽", "👍🏽"),
        ("la familia 👨‍👩‍👧 llega", "👨‍👩‍👧"),
        ("desde 🇪🇸 con cariño", "🇪🇸"),
        ("revisa `parseDraft()` antes", "`parseDraft()`"),
        ("revisa ``a `b` c`` antes", "``a `b` c``"),
        ("escribe a ana@example.com hoy", "ana@example.com"),
        ("mira <https://example.com/x> luego", "<https://example.com/x>"),
        ("mira [esto](https://example.com/x) luego", "[esto](https://example.com/x)"),
    ])
    func protectsInlineMarkup(line: String, expected: String) {
        #expect(protectedSpans(line) == [expected])
    }

    @Test func bareLinksDropTrailingPunctuation() {
        #expect(protectedSpans("¿has visto https://example.com/a?b=c?") == ["https://example.com/a?b=c"])
        #expect(protectedSpans("en (https://example.com/doc).") == ["https://example.com/doc"])
    }

    @Test func formattingMarkersAreProtectedAndMerged() {
        #expect(DraftMarkup.segments(of: "esto es **muy** importante") == [
            .text("esto es "), .protected("**"), .text("muy"), .protected("**"), .text(" importante"),
        ])
        #expect(protectedSpans("**@juan**") == ["**@juan**"])
        #expect(protectedSpans("un ||spoiler||") == ["||", "||"])
    }

    @Test func plainSpanishHasNothingProtected() {
        #expect(DraftMarkup.segments(of: "¿Quedamos mañana a las 10:30?") == [.text("¿Quedamos mañana a las 10:30?")])
        #expect(DraftMarkup.segments(of: "el snake_case se queda") == [.text("el snake_case se queda")])
    }
}
