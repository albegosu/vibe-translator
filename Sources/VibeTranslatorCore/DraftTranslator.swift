import Foundation

/// How protected markup is represented while a line goes through the engine.
public struct PlaceholderStyle: Sendable {
    public let prefix: String
    public let suffix: String

    public init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }

    public static let `default` = PlaceholderStyle(prefix: "{", suffix: "}")

    func token(_ index: Int) -> String { "\(prefix)\(index)\(suffix)" }

    /// Tolerates engines that add spaces inside the token, e.g. `{ 0 }`.
    var pattern: NSRegularExpression {
        DraftMarkup.regex(NSRegularExpression.escapedPattern(for: prefix) + #"\s*(\d+)\s*"# + NSRegularExpression.escapedPattern(for: suffix))
    }
}

public struct EngineFailure: Sendable, Equatable {
    public let engineName: String
    public let message: String
}

public struct DraftTranslation: Sendable, Equatable {
    public let text: String
    /// Lines sent to the engine.
    public let translatedLines: Int
    /// Lines where the engine mangled placeholders and each prose fragment was translated on its own.
    public let fallbackLines: Int
    /// Engine that produced the translation (`nil` if nothing needed translating).
    public let engineName: String?
    /// Engines that were tried first and failed, in order.
    public let failures: [EngineFailure]
}

/// Translates a Discord draft line by line, keeping markup, code, blank lines and
/// indentation untouched. Protected spans travel as placeholders; if the engine
/// does not return every placeholder exactly once, that line falls back to
/// translating its prose fragments separately, so markup is never lost.
///
/// `engines` are tried in order: one that fails, times out or returns something that
/// doesn't look like a translation is skipped for the rest of the draft.
public struct DraftTranslator: Sendable {
    public var engines: [any TranslationEngine]
    public var source: Locale.Language
    public var target: Locale.Language
    public var placeholders: PlaceholderStyle
    public var engineTimeout: Duration?

    public init(
        engines: [any TranslationEngine],
        source: Locale.Language = Locale.Language(identifier: "es"),
        target: Locale.Language = Locale.Language(identifier: "en"),
        placeholders: PlaceholderStyle = .default,
        engineTimeout: Duration? = nil
    ) {
        self.engines = engines
        self.source = source
        self.target = target
        self.placeholders = placeholders
        self.engineTimeout = engineTimeout
    }

    public init(
        engine: any TranslationEngine,
        source: Locale.Language = Locale.Language(identifier: "es"),
        target: Locale.Language = Locale.Language(identifier: "en"),
        placeholders: PlaceholderStyle = .default
    ) {
        self.init(engines: [engine], source: source, target: target, placeholders: placeholders)
    }

    public func translate(_ draft: String) async throws -> DraftTranslation {
        let document = DraftDocument(draft)
        guard !document.lines.isEmpty else {
            return DraftTranslation(text: draft, translatedLines: 0, fallbackLines: 0, engineName: nil, failures: [])
        }

        var chain = EngineChain(engines: engines, source: source, target: target, timeout: engineTimeout)
        let pattern = placeholders.pattern
        var results = [String?](repeating: nil, count: document.lines.count)

        // Pass 1: whole lines with placeholders, so the engine keeps sentence context.
        let placeholderLines = document.lines.indices.filter { document.lines[$0].canUsePlaceholders(pattern) }
        if !placeholderLines.isEmpty {
            let inputs = placeholderLines.map { document.lines[$0].placeholderSource(placeholders) }
            let outputs = try await chain.translate(inputs)
            for (index, output) in zip(placeholderLines, outputs) {
                results[index] = document.lines[index].restore(singleLine(output), pattern: pattern)
            }
        }

        // Pass 2: fragment by fragment for every line that could not be restored.
        let fallbackLines = results.indices.filter { results[$0] == nil }
        if !fallbackLines.isEmpty {
            let fragments = fallbackLines.flatMap { document.lines[$0].translatableFragments }
            let outputs = try await chain.translate(fragments.map(\.core))
            var translated = outputs.map(singleLine).makeIterator()
            for index in fallbackLines {
                results[index] = document.lines[index].assembleFragments { translated.next() ?? $0 }
            }
        }

        let text = document.assemble(results.indices.map { index in
            DraftText.mirroringLeadingCase(of: document.lines[index].content, in: results[index] ?? "")
        })
        return DraftTranslation(
            text: text,
            translatedLines: document.lines.count,
            fallbackLines: fallbackLines.count,
            engineName: chain.lastEngine,
            failures: chain.failures
        )
    }

    /// Each request is a single line; an engine must not introduce line breaks.
    private func singleLine(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Engine fallback

/// Tries engines in order and drops the ones that fail for the rest of the draft,
/// so a slow or unavailable LLM costs at most one timeout.
struct EngineChain {
    private var remaining: [any TranslationEngine]
    let source: Locale.Language
    let target: Locale.Language
    let timeout: Duration?
    private(set) var failures: [EngineFailure] = []
    private(set) var lastEngine: String?

    init(engines: [any TranslationEngine], source: Locale.Language, target: Locale.Language, timeout: Duration?) {
        self.remaining = engines
        self.source = source
        self.target = target
        self.timeout = timeout
    }

    mutating func translate(_ inputs: [String]) async throws -> [String] {
        var lastError: Error = TranslationEngineError.unavailable("No hay ningún motor de traducción configurado.")
        while let engine = remaining.first {
            do {
                let (source, target) = (source, target)
                let call: @Sendable () async throws -> [String] = { try await engine.translate(inputs, from: source, to: target) }
                let outputs = if let timeout { try await withTimeout(timeout, call) } else { try await call() }
                try Self.validate(outputs, for: inputs)
                lastEngine = engine.displayName
                return outputs
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(EngineFailure(engineName: engine.displayName, message: error.localizedDescription))
                lastError = error
                remaining.removeFirst()
            }
        }
        throw lastError
    }

    /// One non-empty line per input, and no wildly longer "translation" (an LLM answering
    /// the message instead of translating it).
    static func validate(_ outputs: [String], for inputs: [String]) throws {
        guard outputs.count == inputs.count else {
            throw TranslationEngineError.resultCountMismatch(expected: inputs.count, got: outputs.count)
        }
        for (input, output) in zip(inputs, outputs) {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= max(input.count * 3, input.count + 80) else {
                throw TranslationEngineError.implausibleOutput
            }
        }
    }
}

// MARK: - Document model

struct DraftDocument {
    enum Piece {
        case verbatim(String)
        case line(Int)
    }

    private(set) var pieces: [Piece] = []
    private(set) var lines: [DraftLine] = []

    init(_ draft: String) {
        let ns = draft as NSString
        var cursor = 0
        for fence in DraftMarkup.codeFence.matches(in: draft, range: NSRange(location: 0, length: ns.length)) {
            addProse(ns.substring(with: NSRange(location: cursor, length: fence.range.location - cursor)))
            pieces.append(.verbatim(ns.substring(with: fence.range)))
            cursor = NSMaxRange(fence.range)
        }
        addProse(ns.substring(from: cursor))
    }

    func assemble(_ translatedLines: [String]) -> String {
        pieces.map { piece in
            switch piece {
            case let .verbatim(text): text
            case let .line(index): lines[index].head + translatedLines[index] + lines[index].tail
            }
        }.joined()
    }

    private mutating func addProse(_ prose: String) {
        for (offset, line) in prose.components(separatedBy: "\n").enumerated() {
            if offset > 0 { pieces.append(.verbatim("\n")) }
            if let parsed = DraftLine(line) {
                pieces.append(.line(lines.count))
                lines.append(parsed)
            } else if !line.isEmpty {
                pieces.append(.verbatim(line))
            }
        }
    }
}

struct DraftLine {
    struct Fragment {
        let leading: String
        let core: String
        let trailing: String
    }

    /// Indentation plus block prefix (`> `, `- `, `# `…), kept verbatim.
    let head: String
    /// Trailing whitespace, kept verbatim.
    let tail: String
    let segments: [DraftSegment]

    /// `nil` when the line has no prose worth translating.
    init?(_ line: String) {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        let headLength = DraftMarkup.blockPrefix.firstMatch(in: line, range: full)?.range.length ?? 0
        let tailStart = DraftMarkup.trailingWhitespace.firstMatch(in: line, range: full)?.range.location ?? ns.length
        guard tailStart > headLength else { return nil }

        let segments = DraftMarkup.segments(of: ns.substring(with: NSRange(location: headLength, length: tailStart - headLength)))
        guard segments.contains(where: { if case let .text(text) = $0 { DraftText.hasLetters(text) } else { false } }) else {
            return nil
        }
        self.head = ns.substring(to: headLength)
        self.tail = ns.substring(from: tailStart)
        self.segments = segments
    }

    /// The line's content as typed, without head and tail.
    var content: String {
        segments.map { segment in
            switch segment {
            case let .text(text), let .protected(text): text
            }
        }.joined()
    }

    private var protectedSpans: [String] {
        segments.compactMap { if case let .protected(span) = $0 { span } else { nil } }
    }

    /// Placeholders are ambiguous if the prose already contains something that looks like one.
    func canUsePlaceholders(_ pattern: NSRegularExpression) -> Bool {
        !segments.contains { segment in
            guard case let .text(text) = segment else { return false }
            return pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }
    }

    func placeholderSource(_ style: PlaceholderStyle) -> String {
        var index = 0
        return segments.map { segment in
            switch segment {
            case let .text(text):
                return text
            case .protected:
                defer { index += 1 }
                return style.token(index)
            }
        }.joined()
    }

    /// Puts protected spans back. Returns `nil` unless every placeholder appears exactly once.
    func restore(_ translated: String, pattern: NSRegularExpression) -> String? {
        let spans = protectedSpans
        let ns = translated as NSString
        let matches = pattern.matches(in: translated, range: NSRange(location: 0, length: ns.length))
        let indices = matches.compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        guard indices.count == spans.count, Set(indices) == Set(spans.indices) else { return nil }

        let restored = NSMutableString(string: translated)
        for (match, index) in zip(matches, indices).reversed() {
            restored.replaceCharacters(in: match.range, with: spans[index])
        }
        return restored as String
    }

    /// Prose fragments that need the engine, with their surrounding whitespace split off.
    var translatableFragments: [Fragment] {
        segments.compactMap { segment in
            guard case let .text(text) = segment, DraftText.hasLetters(text) else { return nil }
            return Self.fragment(text)
        }
    }

    func assembleFragments(_ translate: (String) -> String) -> String {
        segments.map { segment in
            switch segment {
            case let .protected(span):
                return span
            case let .text(text):
                guard DraftText.hasLetters(text) else { return text }
                let fragment = Self.fragment(text)
                return fragment.leading + translate(fragment.core) + fragment.trailing
            }
        }.joined()
    }

    private static func fragment(_ text: String) -> Fragment {
        let core = text.trimmingCharacters(in: .whitespaces)
        guard let coreRange = text.range(of: core) else { return Fragment(leading: "", core: text, trailing: "") }
        return Fragment(
            leading: String(text[..<coreRange.lowerBound]),
            core: core,
            trailing: String(text[coreRange.upperBound...])
        )
    }
}
