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
    case leakedPlaceholders

    public var errorDescription: String? {
        switch self {
        case .languagesNotInstalled:
            String(localized: "Faltan idiomas del traductor de Apple. Descárgalos en Ajustes › Traducción › Apple Translation.")
        case .unsupportedLanguagePair:
            String(localized: "Apple Translation no admite este par de idiomas.")
        case let .unavailable(reason):
            reason
        case let .resultCountMismatch(expected, got):
            String(localized: "El motor devolvió \(got) líneas en lugar de \(expected).")
        case .invalidResponse:
            String(localized: "El motor devolvió una respuesta con un formato no válido.")
        case .implausibleOutput:
            String(localized: "El motor devolvió algo que no parece una traducción.")
        case .timedOut:
            String(localized: "La traducción ha tardado demasiado.")
        case .leakedPlaceholders:
            String(localized: "La traducción traía marcadores internos y no se ha aplicado. Vuelve a intentarlo.")
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
