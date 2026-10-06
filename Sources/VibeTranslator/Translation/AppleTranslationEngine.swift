import Foundation
import Translation
import VibeTranslatorCore

/// On-device translation with Apple's Translation framework (macOS 26+ standalone sessions).
/// `TranslationSession` isn't Sendable, so the cached session lives behind a lock and is
/// only used from nonisolated code (never sent across actors).
final class AppleTranslationEngine: TranslationEngine, @unchecked Sendable {
    let displayName = "Apple Translation (en el dispositivo)"

    private let lock = NSLock()
    private var cached: (key: String, session: TranslationSession)?

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: break
        case .supported: throw TranslationEngineError.languagesNotInstalled
        case .unsupported: throw TranslationEngineError.unsupportedLanguagePair
        @unknown default: throw TranslationEngineError.unsupportedLanguagePair
        }

        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        let responses: [TranslationSession.Response]
        do {
            responses = try await session(from: source, to: target).translations(from: requests)
        } catch TranslationError.notInstalled {
            // Right after a download the status can read "installed" before the model is usable.
            dropCachedSession()
            throw TranslationEngineError.languagesNotInstalled
        }
        guard responses.count == texts.count else {
            throw TranslationEngineError.resultCountMismatch(expected: texts.count, got: responses.count)
        }

        var results = texts
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id), results.indices.contains(index) {
                results[index] = response.targetText
            }
        }
        return results
    }

    private func session(from source: Locale.Language, to target: Locale.Language) -> TranslationSession {
        let key = source.maximalIdentifier + "→" + target.maximalIdentifier
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.key == key {
            return cached.session
        }
        let session = TranslationSession(installedSource: source, target: target)
        cached = (key, session)
        return session
    }

    private func dropCachedSession() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }

    static func availability(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }
}
