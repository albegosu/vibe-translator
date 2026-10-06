import Foundation
import Testing
@testable import VibeTranslatorCore

/// Returns a fixed rewrite (with ⟦n⟧ tokens) and records what it was asked.
actor ScriptedRewriter: TextRewriter {
    nonisolated let displayName: String
    private let output: String
    private(set) var received: [(text: String, instructions: String)] = []

    init(_ displayName: String = "LLM", output: String) {
        self.displayName = displayName
        self.output = output
    }

    func rewrite(_ text: String, instructions: String) async throws -> String {
        received.append((text, instructions))
        return output
    }
}

struct FailingRewriter: TextRewriter {
    let displayName = "Offline LLM"
    func rewrite(_ text: String, instructions: String) async throws -> String {
        throw TranslationEngineError.unavailable("no responde")
    }
}

struct PromptMarkupTests {
    @Test func masksTechnicalContent() {
        let prompt = "mira `parseConfig()` en Sources/App/Config.swift y @docs/api.md, el endpoint https://api.acme.dev/v1 falla con {{user_id}} dentro de <context> y en values.yaml"
        let (masked, spans) = PromptMarkup.mask(prompt)
        #expect(spans == ["`parseConfig()`", "Sources/App/Config.swift", "@docs/api.md", "https://api.acme.dev/v1", "{{user_id}}", "<context>", "values.yaml"])
        #expect(masked == "mira ⟦0⟧ en ⟦1⟧ y ⟦2⟧, el endpoint ⟦3⟧ falla con ⟦4⟧ dentro de ⟦5⟧ y en ⟦6⟧")
    }

    @Test func masksFencedCodeAsOneToken() {
        let (masked, spans) = PromptMarkup.mask("arregla esto:\n```swift\nlet x = 1\n```\ngracias")
        #expect(spans == ["```swift\nlet x = 1\n```"])
        #expect(masked == "arregla esto:\n⟦0⟧\ngracias")
    }

    @Test func unmaskRequiresEveryToken() throws {
        let spans = ["`a`", "b.swift"]
        #expect(try PromptMarkup.unmask("use ⟦1⟧ then ⟦0⟧", spans: spans) == "use b.swift then `a`")
        #expect(try PromptMarkup.unmask("⟦0⟧ and again ⟦0⟧ in ⟦1⟧", spans: spans) == "`a` and again `a` in b.swift")
        #expect(throws: PromptImproveError.placeholdersLost) { try PromptMarkup.unmask("use ⟦0⟧", spans: spans) }
        #expect(throws: PromptImproveError.placeholdersLost) { try PromptMarkup.unmask("use ⟦0⟧ ⟦1⟧ ⟦7⟧", spans: spans) }
    }

    @Test func codeBlocksAppearOnceAndOnTheirOwnLines() throws {
        let spans = ["```swift\nlet x = 1\n```"]
        #expect(try PromptMarkup.unmask("The bug is likely in ⟦0⟧.", spans: spans) == "The bug is likely in:\n```swift\nlet x = 1\n```")
        #expect(try PromptMarkup.unmask("The test in ⟦0⟧ fails often.", spans: spans) == "The test in:\n```swift\nlet x = 1\n```\nfails often.")
        #expect(try PromptMarkup.unmask("This code:⟦0⟧", spans: spans) == "This code:\n```swift\nlet x = 1\n```")
        #expect(try PromptMarkup.unmask("Context:\n⟦0⟧\nDone", spans: spans) == "Context:\n```swift\nlet x = 1\n```\nDone")
        #expect(throws: PromptImproveError.placeholdersLost) { try PromptMarkup.unmask("⟦0⟧\n⟦0⟧", spans: spans) }
    }
}

struct PromptImproverTests {
    private let rough = "oye, el login de @src/auth/ peta cuando el token caduca, míralo y añade tests en LoginTests.swift"

    @Test func rewritesAndRestoresTokens() async throws {
        let llm = ScriptedRewriter(output: "## Goal\nFix the login in ⟦0⟧ when the token expires.\n\n## Done when\n- Tests in ⟦1⟧ cover it")
        let result = try await PromptImprover(rewriters: [llm]).improve(rough)
        #expect(result.text == "## Goal\nFix the login in @src/auth/ when the token expires.\n\n## Done when\n- Tests in LoginTests.swift cover it")
        #expect(result.engineName == "LLM")
        #expect(!result.translatedOnly)
        let sent = await llm.received.first
        #expect(sent?.text == "oye, el login de ⟦0⟧ peta cuando el token caduca, míralo y añade tests en ⟦1⟧")
        #expect(sent?.instructions.contains("in English") == true)
        #expect(sent?.instructions.contains("## Goal") == true)
    }

    @Test func fallsBackToTheNextRewriterWhenTokensAreLost() async throws {
        let sloppy = ScriptedRewriter("Sloppy", output: "Fix the login.")
        let careful = ScriptedRewriter("Careful", output: "Fix ⟦0⟧ and test it in ⟦1⟧.")
        let result = try await PromptImprover(rewriters: [sloppy, careful]).improve(rough)
        #expect(result.text == "Fix @src/auth/ and test it in LoginTests.swift.")
        #expect(result.failures.map(\.engineName) == ["Sloppy"])
    }

    @Test func rejectsAModelThatWritesCode() async throws {
        let eager = ScriptedRewriter("Eager", output: "Here's the fix:\n```swift\nfunc refresh() {}\n```\n⟦0⟧ ⟦1⟧")
        let result = try await PromptImprover(rewriters: [eager, ScriptedRewriter(output: "⟦0⟧ ⟦1⟧ fix")]).improve(rough)
        #expect(result.failures.first?.message == PromptImproveError.answeredInsteadOfRewriting.errorDescription)
    }

    @Test func translatesWhenEveryRewriterFails() async throws {
        let improver = PromptImprover(rewriters: [FailingRewriter()], fallback: DraftTranslator(engine: UppercaseEngine()))
        let result = try await improver.improve("Revisa el login")
        #expect(result.translatedOnly)
        #expect(result.text == "REVISA EL LOGIN")
        #expect(result.failures.map(\.engineName) == ["Offline LLM"])
    }

    @Test func keepingTheLanguageMeansNoTranslationFallback() async {
        let improver = PromptImprover(rewriters: [FailingRewriter()], fallback: DraftTranslator(engine: UppercaseEngine()), options: PromptOptions(toEnglish: false))
        await #expect(throws: TranslationEngineError.unavailable("Offline LLM: no responde")) {
            try await improver.improve("Revisa el login")
        }
    }

    @Test func instructionsFollowTheOptions() {
        let concise = PromptOptions(profile: .concise, toEnglish: false, glossary: ["PR"]).instructions
        #expect(concise.contains("same language"))
        #expect(concise.contains("no headings"))
        #expect(concise.contains("Keep these terms exactly as written: PR."))
    }

    @Test func parsesThePromptField() {
        #expect(LLMPrompt.parsePrompt(#"{"prompt": "Fix it"}"#) == "Fix it")
        #expect(LLMPrompt.parsePrompt("```json\n{\"prompt\": \"Fix it\"}\n```") == "Fix it")
        #expect(LLMPrompt.parsePrompt("Fix it") == "Fix it")
    }
}
