import Foundation

/// An engine that can rewrite a whole text following instructions (LLMs only).
public protocol TextRewriter: Sendable {
    var displayName: String { get }
    func rewrite(_ text: String, instructions: String) async throws -> String
}

public enum PromptProfile: String, CaseIterable, Identifiable, Sendable {
    case agentTask
    case concise

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agentTask: "Tarea para agente de código"
        case .concise: "Pregunta concisa"
        }
    }

    var guidance: String {
        switch self {
        case .agentTask:
            """
            The prompt is a task for an AI coding agent. Match the structure to the size of the request:
            - Small request (one or two things to do): one or two clear sentences, optionally followed by a few bullets \
            with constraints. No headings.
            - Larger request (several steps, constraints or context): short Markdown sections, only the ones that add \
            information, from "## Goal", "## Context", "## Requirements" and "## Done when".
            """
        case .concise:
            "The prompt is a question or request for an AI assistant. Write one or two short, direct paragraphs; no headings."
        }
    }
}

public struct PromptOptions: Equatable, Sendable {
    public var profile: PromptProfile
    /// Write the prompt in English (otherwise keep the author's language).
    public var toEnglish: Bool
    public var glossary: [String]

    public init(profile: PromptProfile = .agentTask, toEnglish: Bool = true, glossary: [String] = []) {
        self.profile = profile
        self.toEnglish = toEnglish
        self.glossary = glossary
    }

    public var instructions: String {
        var rules = [
            "Keep the author's intent, facts and scope. Never add requirements, technologies, numbers or assumptions they didn't state.",
            "Do not answer the request or start doing it: no solutions, no code, no explanations. Only rewrite the request.",
            "Tokens such as ⟦0⟧ or ⟦1⟧ stand for code, file paths, @mentions, URLs, variables or tags. Keep every token; you may repeat one when you refer to the same thing again.",
            "Only code blocks appear as a token alone on its own line in the input; keep each of those on its own line (for example at the end of the Context section). Every other token (paths, names, links) belongs inside a sentence: never put it alone on a line or in a list of its own.",
            "Make it clearer, not longer: remove filler and repetition, and add structure only where it helps. The result should rarely be more than twice as long as the request.",
            "Say each thing once; never repeat the same point in two places.",
            "Use precise wording: pick one term instead of alternatives joined by slashes.",
            "No role-play preambles (\"You are an expert…\") and no generic advice.",
            "Only if the agent truly cannot proceed without some information, end with a short \"Open questions\" list instead of guessing.",
            #"Return JSON: {"prompt": "<the rewritten prompt>"}."#,
        ]
        if !glossary.isEmpty {
            rules.insert("Keep these terms exactly as written: \(glossary.joined(separator: ", ")).", at: 3)
        }
        let language = toEnglish
            ? "Write the rewritten prompt in English, translating the author's words by meaning."
            : "Write the rewritten prompt in the same language the author used."
        return """
        You turn a developer's rough request into a clear, well-structured prompt for an AI assistant.

        \(language)

        \(profile.guidance)

        Rules:
        \(rules.map { "- " + $0 }.joined(separator: "\n"))
        """
    }
}

public enum PromptImproveError: LocalizedError, Equatable {
    case nothingToImprove
    case placeholdersLost
    case answeredInsteadOfRewriting
    case noRewriter

    public var errorDescription: String? {
        switch self {
        case .nothingToImprove: "No hay texto que mejorar."
        case .placeholdersLost: "El modelo perdió parte del código, rutas o menciones del prompt."
        case .answeredInsteadOfRewriting: "El modelo respondió al prompt en vez de reescribirlo."
        case .noRewriter: "Mejorar prompt necesita un motor LLM (Ollama o Apple Intelligence)."
        }
    }
}

public struct PromptImprovement: Sendable, Equatable {
    public let text: String
    public let engineName: String
    /// Every rewriter failed and the prompt was only translated.
    public let translatedOnly: Bool
    public let failures: [EngineFailure]
}

/// Technical content that must survive a prompt rewrite verbatim.
public enum PromptMarkup {
    static let protected = DraftMarkup.regex([
        "```[\\s\\S]*?(?:```|\\z)",                                   // fenced code (an unclosed fence runs to the end)
        #"``(?:[^`]|`(?!`))+``|`[^`\n]+`"#,                          // inline code
        #"<?https?://[^\s<>]*[^\s<>.,:;"'!?)\]]>?"#,                 // URLs
        #"\{\{[^{}\n]+\}\}|\$\{[^{}\n]+\}"#,                          // template variables
        #"</?[A-Za-z][\w:.-]*(?:\s[^<>\n]*)?/?>"#,                    // XML / HTML tags
        #"(?<![\w@])@[\w.\-/]*[\w/]"#,                                // @file, @folder/, @mention
        #"(?<![\w/])(?:~|\.{1,2})?/?(?:[\w.\-]+/)+[\w.\-]*[\w]"#,      // paths with at least one slash
        #"\b[\w\-]+\.(?:swift|m|h|c|cc|cpp|rs|go|py|rb|js|jsx|ts|tsx|java|kt|kts|cs|php|sql|sh|zsh|json|ya?ml|toml|ini|env|md|txt|html|css|scss|xml|plist|lock|gradle|tf)\b"#, // bare file names
    ].joined(separator: "|"))

    static let placeholders = PlaceholderStyle(prefix: "⟦", suffix: "⟧")

    /// Replaces protected spans with ⟦n⟧ tokens.
    public static func mask(_ text: String) -> (masked: String, spans: [String]) {
        let ns = text as NSString
        let masked = NSMutableString(string: text)
        var spans: [String] = []
        let matches = protected.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            spans.append(ns.substring(with: match.range))
        }
        for (index, match) in matches.enumerated().reversed() {
            masked.replaceCharacters(in: match.range, with: placeholders.token(index))
        }
        return (masked as String, spans)
    }

    /// Puts the spans back. Every token must survive; a rewrite may mention a path or
    /// @mention twice, but a multi-line code block must appear exactly once and is always
    /// put back on lines of its own so the Markdown stays valid.
    public static func unmask(_ text: String, spans: [String]) throws -> String {
        let pattern = placeholders.pattern
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let indices = matches.map { Int(ns.substring(with: $0.range(at: 1))) ?? -1 }
        guard Set(indices) == Set(spans.indices) else { throw PromptImproveError.placeholdersLost }
        for (index, span) in spans.enumerated() where span.contains("\n") {
            guard indices.filter({ $0 == index }).count == 1 else { throw PromptImproveError.placeholdersLost }
        }

        let restored = NSMutableString(string: text)
        for (match, index) in zip(matches, indices).reversed() {
            let span = spans[index]
            if span.contains("\n") {
                let (range, replacement) = blockPlacement(span, at: match.range, in: restored)
                restored.replaceCharacters(in: range, with: replacement)
            } else {
                restored.replaceCharacters(in: match.range, with: span)
            }
        }
        return restored as String
    }

    /// Models sometimes put a code block mid-sentence ("the bug is in ⟦2⟧."). Close the
    /// sentence with a colon, drop the stray punctuation after it and give the block its own lines.
    private static func blockPlacement(_ block: String, at token: NSRange, in text: NSMutableString) -> (NSRange, String) {
        func char(_ index: Int) -> Character { Character(text.substring(with: NSRange(location: index, length: 1))) }
        var start = token.location
        while start > 0, char(start - 1) == " " || char(start - 1) == "\t" { start -= 1 }
        var end = NSMaxRange(token)
        if end < text.length, ".,;".contains(char(end)) { end += 1 }
        while end < text.length, char(end) == " " || char(end) == "\t" { end += 1 }

        var prefix = ""
        if start > 0, char(start - 1) != "\n" {
            prefix = (char(start - 1).isLetter || char(start - 1).isNumber ? ":" : "") + "\n"
        }
        let suffix = end < text.length && char(end) != "\n" ? "\n" : ""
        return (NSRange(location: start, length: end - start), prefix + block + suffix)
    }
}

/// Rewrites a rough prompt into a structured one (optionally in English), keeping code,
/// paths, @mentions, URLs, variables and tags intact. Rewriters are tried in order; if all
/// fail and English was requested, the prompt is at least translated by `fallback`.
public struct PromptImprover: Sendable {
    public var rewriters: [any TextRewriter]
    public var fallback: DraftTranslator?
    public var options: PromptOptions
    public var timeout: Duration?

    public init(rewriters: [any TextRewriter], fallback: DraftTranslator? = nil, options: PromptOptions = PromptOptions(), timeout: Duration? = nil) {
        self.rewriters = rewriters
        self.fallback = fallback
        self.options = options
        self.timeout = timeout
    }

    public func improve(_ text: String) async throws -> PromptImprovement {
        guard DraftText.hasLetters(text) else { throw PromptImproveError.nothingToImprove }
        if text.contains(PromptMarkup.placeholders.prefix) {
            // Our own token syntax in the input would be ambiguous; only translation is safe.
            return try await translateOnly(text, failures: [])
        }

        let (masked, spans) = PromptMarkup.mask(text)
        let instructions = options.instructions
        var failures: [EngineFailure] = []
        for rewriter in rewriters {
            do {
                let call: @Sendable () async throws -> String = { try await rewriter.rewrite(masked, instructions: instructions) }
                let output = if let timeout { try await withTimeout(timeout, call) } else { try await call() }
                let result = try validated(output, masked: masked, spans: spans)
                return PromptImprovement(text: result, engineName: rewriter.displayName, translatedOnly: false, failures: failures)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(EngineFailure(engineName: rewriter.displayName, message: error.localizedDescription))
            }
        }
        return try await translateOnly(text, failures: failures)
    }

    private func validated(_ output: String, masked: String, spans: [String]) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DraftText.hasLetters(trimmed), trimmed.count <= max(masked.count * 5, masked.count + 1_500) else {
            throw TranslationEngineError.implausibleOutput
        }
        // Every code fence of the input is a token, so a fence in the output is the model writing code.
        guard !trimmed.contains("```") else { throw PromptImproveError.answeredInsteadOfRewriting }
        return try PromptMarkup.unmask(trimmed, spans: spans)
    }

    private func translateOnly(_ text: String, failures: [EngineFailure]) async throws -> PromptImprovement {
        guard options.toEnglish, let fallback else {
            if let last = failures.last { throw TranslationEngineError.unavailable("\(last.engineName): \(last.message)") }
            throw PromptImproveError.noRewriter
        }
        let translation = try await fallback.translate(text)
        return PromptImprovement(
            text: translation.text,
            engineName: translation.engineName ?? "traducción",
            translatedOnly: true,
            failures: failures + translation.failures
        )
    }
}

extension LLMPrompt {
    /// JSON schema for prompt rewrites: `{"prompt": "..."}`.
    public static var promptSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["prompt": ["type": "string"]],
            "required": ["prompt"],
        ]
    }

    /// Accepts `{"prompt": "..."}` (tolerating fences or chatter around it); otherwise the raw text.
    public static func parsePrompt(_ response: String) -> String {
        if let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start < end,
           let object = try? JSONSerialization.jsonObject(with: Data(response[start...end].utf8)) as? [String: Any],
           let prompt = object["prompt"] as? String {
            return prompt
        }
        return response
    }
}
