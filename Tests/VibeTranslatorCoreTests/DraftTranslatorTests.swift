import Foundation
import Testing
@testable import VibeTranslatorCore

/// Uppercases prose and leaves `{n}` placeholders alone, so assertions can tell
/// translated text (uppercase) from protected markup (original case).
struct UppercaseEngine: TranslationEngine {
    let displayName = "Uppercase"
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        texts.map { $0.uppercased() }
    }
}

/// Simulates an engine that drops or duplicates placeholders.
struct PlaceholderMangler: TranslationEngine {
    let displayName = "Mangler"
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        texts.map { text in
            text.replacingOccurrences(of: "{0}", with: "").replacingOccurrences(of: "{1}", with: "{1} {1}").uppercased()
        }
    }
}

struct FailingEngine: TranslationEngine {
    let displayName = "Failing"
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        throw TranslationEngineError.languagesNotInstalled
    }
}

/// Records every batch it receives.
actor RecordingEngine: TranslationEngine {
    nonisolated let displayName = "Recording"
    private(set) var batches: [[String]] = []
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        batches.append(texts)
        return texts
    }
}

struct DraftTranslatorTests {
    private func translate(_ draft: String, engine: any TranslationEngine = UppercaseEngine()) async throws -> DraftTranslation {
        try await DraftTranslator(engine: engine).translate(draft)
    }

    @Test func keepsMentionsEmojisLinksAndCode() async throws {
        let draft = "Hola <@123456789012345678>, mira https://example.com/a?b=c y `npm test` :fire: 🎉"
        let result = try await translate(draft)
        #expect(result.text == "HOLA <@123456789012345678>, MIRA https://example.com/a?b=c Y `npm test` :fire: 🎉")
        #expect(result.fallbackLines == 0)
    }

    @Test func keepsLineBreaksBlankLinesAndIndentation() async throws {
        let draft = "Primera línea\n\n  Segunda línea  \nTercera"
        let result = try await translate(draft)
        #expect(result.text == "PRIMERA LÍNEA\n\n  SEGUNDA LÍNEA  \nTERCERA")
        #expect(result.translatedLines == 3)
    }

    @Test func keepsCodeBlocksUntouched() async throws {
        let draft = "Mira esto:\n```swift\nlet saludo = \"hola\"\n```\nY dime"
        let result = try await translate(draft)
        #expect(result.text == "MIRA ESTO:\n```swift\nlet saludo = \"hola\"\n```\nY DIME")
    }

    @Test func unclosedFenceProtectsTheRest() async throws {
        let result = try await translate("Arreglado en\n```\nsin cerrar")
        #expect(result.text == "ARREGLADO EN\n```\nsin cerrar")
    }

    @Test func keepsBlockPrefixes() async throws {
        let draft = "> Cita\n- Punto uno\n1. Paso\n# Título\n-# Nota"
        let result = try await translate(draft)
        #expect(result.text == "> CITA\n- PUNTO UNO\n1. PASO\n# TÍTULO\n-# NOTA")
    }

    @Test func keepsFormattingMarkers() async throws {
        let result = try await translate("Esto es **muy** importante y ||secreto||")
        #expect(result.text == "ESTO ES **MUY** IMPORTANTE Y ||SECRETO||")
    }

    @Test func fallsBackToFragmentsWhenPlaceholdersAreMangled() async throws {
        let draft = "Hola <@123456789012345678>, ¿vienes a <#123456789012345678> luego?"
        let result = try await translate(draft, engine: PlaceholderMangler())
        #expect(result.text == "HOLA <@123456789012345678>, ¿VIENES A <#123456789012345678> LUEGO?")
        #expect(result.fallbackLines == 1)
    }

    @Test func proseThatLooksLikePlaceholdersSkipsStraightToFragments() async throws {
        let engine = RecordingEngine()
        let result = try await translate("usa {0} con <@123456789012345678> ya", engine: engine)
        #expect(result.text == "usa {0} con <@123456789012345678> ya")
        #expect(result.fallbackLines == 1)
        #expect(await engine.batches == [["usa {0} con", "ya"]])
    }

    @Test func linesWithoutProseAreNotSentToTheEngine() async throws {
        let engine = RecordingEngine()
        let result = try await translate("👍\n<@123456789012345678>\nvale\nhttps://example.com", engine: engine)
        #expect(result.text == "👍\n<@123456789012345678>\nvale\nhttps://example.com")
        #expect(await engine.batches == [["vale"]])
    }

    @Test func draftWithoutProseNeverCallsTheEngine() async throws {
        let engine = RecordingEngine()
        let result = try await translate("🎉 <@123456789012345678>", engine: engine)
        #expect(result.text == "🎉 <@123456789012345678>")
        #expect(result.translatedLines == 0)
        #expect(await engine.batches.isEmpty)
    }

    @Test func propagatesEngineErrors() async {
        await #expect(throws: TranslationEngineError.languagesNotInstalled) {
            try await translate("hola", engine: FailingEngine())
        }
    }
}

struct DraftTextTests {
    @Test func comparisonIgnoresEditorNoise() {
        #expect(DraftText.isSame("hola\u{00A0}mundo\r\nadiós\n", "hola mundo\nadiós"))
        #expect(DraftText.isSame("hola\u{200B}", "hola"))
        #expect(DraftText.isSame("We\u{2019}ll see \u{201C}it\u{201D}", "We'll see \"it\""))
        #expect(DraftText.isSame("uno\u{2028}dos", "uno\ndos"))
        #expect(!DraftText.isSame("hola mundo", "hola  mundo"))
    }
}

struct LeadingCaseTests {
    @Test(arguments: [
        ("tío, no me ralles", "Dude, don't stress me out", "dude, don't stress me out"),
        ("¿Hacemos rollback?", "do we roll back?", "Do we roll back?"),
        ("vale, lo miro yo", "I'll take a look", "I'll take a look"),
        ("vale", "Okay", "okay"),
        ("Hola", "hey", "Hey"),
        ("@juan mira esto", "Look at this", "Look at this"),
        ("**ojo** con esto", "Watch out for this", "Watch out for this"),
        ("hola", "<@123456789012345678> hi", "<@123456789012345678> hi"),
    ])
    func mirrorsTheFirstLetter(source: String, translation: String, expected: String) {
        #expect(DraftText.mirroringLeadingCase(of: source, in: translation) == expected)
    }

    @Test func appliesPerLineInThePipeline() async throws {
        let llm = CannedEngine(displayName: "LLM", outputs: ["Dude, wait", "Do we ship it?"])
        let result = try await DraftTranslator(engine: llm).translate("tío, espera\n¿Lo subimos?")
        #expect(result.text == "dude, wait\nDo we ship it?")
    }
}

struct LanguageDirectionTests {
    private let spanish = TranslationLanguage.spanishSpain
    private let english = TranslationLanguage.englishUS

    @Test(arguments: [
        ("Hey <@123456789012345678>, did you check the PR? It's still failing in CI", "en", "es"),
        ("Oye, ¿has mirado el PR? Sigue fallando en CI", "es", "en"),
        ("no te rayes, mañana lo miramos con calma", "es", "en"),
        ("lgtm, ship it once the tests pass", "en", "es"),
    ])
    func picksTheDirection(text: String, source: String, target: String) {
        let direction = LanguageDirection.detect(text, native: spanish, target: english)
        #expect(direction.source.languageCode?.identifier == source)
        #expect(direction.target.languageCode?.identifier == target)
    }

    @Test func otherPairsWork() {
        let french = TranslationLanguage("fr-FR")
        let toEnglish = LanguageDirection.detect("Salut, tu peux regarder la PR quand tu as un moment ?", native: french, target: english)
        #expect(toEnglish.source.languageCode?.identifier == "fr")
        #expect(toEnglish.target.languageCode?.identifier == "en")
        let toFrench = LanguageDirection.detect("Can you take a look at the PR when you get a sec?", native: french, target: english)
        #expect(toFrench.target.languageCode?.identifier == "fr")
    }

    @Test func aThirdLanguageComesToMine() {
        let direction = LanguageDirection.detect("Kannst du dir den Pull Request heute noch ansehen?", native: spanish, target: english)
        #expect(direction.source.languageCode?.identifier == "de")
        #expect(direction.target.languageCode?.identifier == "es")
    }

    @Test(arguments: [("vale", "es"), ("ok", "en")])
    func shortTextIsDecidedBetweenMyTwoLanguages(text: String, source: String) {
        #expect(LanguageDirection.detect(text, native: spanish, target: english).source.languageCode?.identifier == source)
    }

    @Test func unknownTextComesToMyLanguage() {
        #expect(LanguageDirection.detect("👍 <@123456789012345678>", native: spanish, target: english).target.languageCode?.identifier == "es")
    }
}

struct TranslationLanguageTests {
    @Test(arguments: [
        ("es-ES", "Spanish (Spain)"),
        ("es-419", "neutral Latin American Spanish (use \"tú\", no voseo or country-specific slang)"),
        ("es-AR", "Spanish (Argentina)"),
        ("en-GB", "English (United Kingdom)"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("zh-Hant", "Chinese (Traditional)"),
        ("ar", "Arabic"),
    ])
    func promptNamesIncludeTheVariant(id: String, expected: String) {
        #expect(LLMPrompt.languageName(Locale.Language(identifier: id)) == expected)
    }

    @Test func displayNamesAreCapitalised() {
        #expect(TranslationLanguage("es-ES").displayName(in: Locale(identifier: "es")) == "Español (España)")
        #expect(TranslationLanguage("en-GB").displayName(in: Locale(identifier: "en")) == "English (United Kingdom)")
    }

    @Test func catalogHasTheDefaultsAndNoDuplicates() {
        let ids = TranslationLanguage.catalog.map(\.id)
        #expect(ids.contains("es-ES") && ids.contains("en-US"))
        #expect(Set(ids).count == ids.count)
        #expect(TranslationLanguage("es-419").isSameLanguage(as: .spanishSpain))
    }
}
