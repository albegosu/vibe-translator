import Foundation

/// A pluggable translation backend. Implementations receive prose with markup replaced
/// by `{n}` placeholders (never raw Discord markup) and must return one translation per
/// input, in order.
public protocol TranslationEngine: Sendable {
    var displayName: String { get }
    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String]
}

public enum TranslationEngineError: LocalizedError, Equatable {
    case languagesNotInstalled
    case unsupportedLanguagePair
    case unavailable(String)
    case resultCountMismatch(expected: Int, got: Int)
    case invalidResponse
    case implausibleOutput
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .languagesNotInstalled:
            "Faltan los idiomas español e inglés del traductor de Apple. Descárgalos desde el menú: Idiomas de traducción…"
        case .unsupportedLanguagePair:
            "El motor de traducción no admite español → inglés."
        case let .unavailable(reason):
            reason
        case let .resultCountMismatch(expected, got):
            "El motor devolvió \(got) líneas en lugar de \(expected)."
        case .invalidResponse:
            "El motor devolvió una respuesta con un formato no válido."
        case .implausibleOutput:
            "El motor devolvió algo que no parece una traducción."
        case .timedOut:
            "La traducción ha tardado demasiado."
        }
    }
}

/// Races `operation` against a deadline so a stuck engine can't block a translation forever.
public func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TranslationEngineError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TranslationEngineError.timedOut }
        return result
    }
}
