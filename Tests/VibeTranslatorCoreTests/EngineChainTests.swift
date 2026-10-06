import Foundation
import Testing
@testable import VibeTranslatorCore

/// Returns canned outputs regardless of input.
struct CannedEngine: TranslationEngine {
    let displayName: String
    let outputs: [String]
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        outputs
    }
}

struct SlowEngine: TranslationEngine {
    let displayName = "Slow"
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        try await Task.sleep(for: .seconds(5))
        return texts
    }
}

/// Counts calls, to prove a failed engine is not retried within the same draft.
actor CountingFailingEngine: TranslationEngine {
    nonisolated let displayName = "Flaky LLM"
    private(set) var calls = 0
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        calls += 1
        throw TranslationEngineError.unavailable("modelo no listo")
    }
}

struct EngineChainTests {
    @Test func usesThePrimaryEngineWhenItWorks() async throws {
        let result = try await DraftTranslator(engines: [UppercaseEngine(), FailingEngine()]).translate("Hola")
        #expect(result.text == "HOLA")
        #expect(result.engineName == "Uppercase")
        #expect(result.failures.isEmpty)
    }

    @Test func fallsBackWhenThePrimaryThrows() async throws {
        let primary = CountingFailingEngine()
        // The mangler forces a second (fragment) pass: the failed primary must not be called again.
        let draft = "Hola <@123456789012345678>, ¿vienes a <#123456789012345678> luego?"
        let result = try await DraftTranslator(engines: [primary, PlaceholderMangler()]).translate(draft)
        #expect(result.text == "HOLA <@123456789012345678>, ¿VIENES A <#123456789012345678> LUEGO?")
        #expect(result.engineName == "Mangler")
        #expect(result.failures == [EngineFailure(engineName: "Flaky LLM", message: "modelo no listo")])
        #expect(await primary.calls == 1)
    }

    @Test func fallsBackWhenLineCountIsWrong() async throws {
        let llm = CannedEngine(displayName: "LLM", outputs: ["only one line"])
        let result = try await DraftTranslator(engines: [llm, UppercaseEngine()]).translate("Uno\nDos")
        #expect(result.text == "UNO\nDOS")
        #expect(result.failures.map(\.engineName) == ["LLM"])
    }

    @Test func rejectsAnAnswerInsteadOfATranslation() async throws {
        let chatty = CannedEngine(displayName: "Chatty", outputs: [String(repeating: "Sure! Here is a long answer. ", count: 10)])
        let result = try await DraftTranslator(engines: [chatty, UppercaseEngine()]).translate("¿Qué hora es?")
        #expect(result.text == "¿QUÉ HORA ES?")
        #expect(result.failures.first?.message == TranslationEngineError.implausibleOutput.errorDescription)
    }

    @Test func timesOutASlowEngine() async throws {
        let translator = DraftTranslator(engines: [SlowEngine(), UppercaseEngine()], engineTimeout: .milliseconds(100))
        let result = try await translator.translate("Hola")
        #expect(result.text == "HOLA")
        #expect(result.failures.first?.message == TranslationEngineError.timedOut.errorDescription)
    }

    @Test func throwsTheLastErrorWhenEveryEngineFails() async {
        await #expect(throws: TranslationEngineError.languagesNotInstalled) {
            try await DraftTranslator(engines: [CountingFailingEngine(), FailingEngine()]).translate("hola")
        }
    }
}

struct LLMPromptTests {
    @Test func instructionsIncludeToneGlossaryAndExtras() {
        let style = TranslationStyle(tone: .relaxedTechnical, glossary: ["PR", "deploy"], extraInstructions: "Use British spelling.")
        let text = LLMPrompt.instructions(for: style)
        #expect(text.contains("software engineer"))
        #expect(text.contains("Keep these terms exactly as written: PR, deploy."))
        #expect(text.hasSuffix("Use British spelling."))
    }

    @Test func payloadIsAJSONObjectWithLines() {
        #expect(LLMPrompt.payload(["hola {0}", "¿qué tal?"]) == #"{"lines":["hola {0}","¿qué tal?"]}"#)
    }

    @Test(arguments: [
        #"{"lines": ["hello {0}", "how are you?"]}"#,
        "```json\n{\"lines\": [\"hello {0}\", \"how are you?\"]}\n```",
        #"Here you go: ["hello {0}", "how are you?"]"#,
    ])
    func parsesTolerantly(response: String) throws {
        #expect(try LLMPrompt.parseLines(response) == ["hello {0}", "how are you?"])
    }

    @Test func rejectsGarbage() {
        #expect(throws: TranslationEngineError.invalidResponse) { try LLMPrompt.parseLines("I can't help with that.") }
    }

    @Test func glossaryParsing() {
        #expect(TranslationStyle.glossary(from: "PR, deploy\nmerge ,, ") == ["PR", "deploy", "merge"])
    }
}

/// Drops the placeholder in the full line (forcing the fragment pass) and, like a real
/// LLM told about tokens, invents one after a lone greeting.
struct TokenInventingEngine: TranslationEngine {
    let displayName = "Inventive LLM"
    func translate(_ texts: [String], from: Locale.Language, to: Locale.Language) async throws -> [String] {
        texts.map { text in
            switch text {
            case "Hola {0}, estoy aquí": "Hey, I'm here"
            case "Hola": "Hey {0}"
            case ", estoy aquí": ", I'm here"
            default: text
            }
        }
    }
}

struct PlaceholderLeakTests {
    @Test func fragmentsNeverKeepInventedTokens() async throws {
        let result = try await DraftTranslator(engine: TokenInventingEngine()).translate("Hola <@123456789012345678>, estoy aquí")
        #expect(result.text == "Hey <@123456789012345678>, I'm here")
        #expect(!result.text.contains("{0}"))
    }

    @Test func removesOnlyInventedTokens() {
        let pattern = PlaceholderStyle.default.pattern
        #expect(DraftTranslator.removingInventedTokens("Hey {0}, use {1} here", source: "Hola, usa {1} aquí", pattern: pattern) == "Hey, use {1} here")
        #expect(DraftTranslator.removingInventedTokens("Hey {0}", source: "Hola", pattern: pattern) == "Hey")
        #expect(DraftTranslator.removingInventedTokens("Format {0}-{1}", source: "Formato {0}-{1}", pattern: pattern) == "Format {0}-{1}")
    }

    @Test func tokensTheAuthorWroteSurvive() async throws {
        // Literal "{0}" typed by the user goes through the fragment pass untouched.
        let result = try await DraftTranslator(engine: RecordingEngine()).translate("usa {0} con <@123456789012345678> ya")
        #expect(result.text == "usa {0} con <@123456789012345678> ya")
    }
}
