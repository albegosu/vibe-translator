import Foundation
import FoundationModels
import VibeTranslatorCore

@Generable
struct TranslatedLines {
    @Guide(description: "One English translation per input line, in the same order")
    var lines: [String]
}

/// Apple's on-device LLM (Apple Intelligence). Follows the style profile and translates
/// the whole draft in one request so every line has context. Private and offline.
final class AppleIntelligenceEngine: TranslationEngine, @unchecked Sendable {
    let displayName = "Apple Intelligence"
    let style: TranslationStyle

    init(style: TranslationStyle) {
        self.style = style
    }

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        // Translating user text is a content transformation: don't refuse a draft for its swearing.
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        if let reason = Self.unavailableReason(model.availability) {
            throw TranslationEngineError.unavailable(reason)
        }

        let instructions = LLMPrompt.instructions(for: style, from: source, to: target)
        let prompt = LLMPrompt.payload(texts)
        let options = GenerationOptions(temperature: 0.2)
        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            return try await session.respond(to: prompt, generating: TranslatedLines.self, options: options).content.lines
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            // Permissive guardrails apply to plain-text responses; retry unstructured.
            let session = LanguageModelSession(model: model, instructions: instructions)
            return try LLMPrompt.parseLines(try await session.respond(to: prompt, options: options).content)
        }
    }

    static var statusText: String {
        unavailableReason(SystemLanguageModel.default.availability) ?? "Disponible"
    }

    static func unavailableReason(_ availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "Este Mac no admite Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence está desactivado en Ajustes del Sistema."
        case .unavailable(.modelNotReady):
            "El modelo de Apple Intelligence aún se está descargando o preparando."
        case .unavailable:
            "Apple Intelligence no está disponible."
        }
    }
}
