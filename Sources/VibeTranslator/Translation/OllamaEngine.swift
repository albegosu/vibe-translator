import Foundation
import VibeTranslatorCore

struct OllamaModel: Identifiable, Hashable, Sendable {
    let name: String
    /// `…:cloud` / `…-cloud` models run on Ollama's servers: the draft leaves the Mac.
    var isCloud: Bool { name.hasSuffix("cloud") }
    var id: String { name }
}

/// A model served by Ollama (local by default). Uses `/api/chat` with a JSON schema
/// so the reply is always `{"lines": [...]}`.
final class OllamaEngine: TranslationEngine, @unchecked Sendable {
    let baseURL: URL
    let model: String
    let style: TranslationStyle

    init(baseURL: URL, model: String, style: TranslationStyle) {
        self.baseURL = baseURL
        self.model = model
        self.style = style
    }

    var displayName: String { "Ollama (\(model))" }

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        guard !model.isEmpty else { throw TranslationEngineError.unavailable("Elige un modelo de Ollama en Ajustes.") }

        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": "30m",
            "think": false,
            "format": LLMPrompt.responseSchema,
            "options": ["temperature": 0.2],
            "messages": [
                ["role": "system", "content": LLMPrompt.instructions(for: style, from: source, to: target)],
                ["role": "user", "content": LLMPrompt.payload(texts)],
            ],
        ]
        do {
            return try LLMPrompt.parseLines(try await chat(body))
        } catch let OllamaError.server(message) where message.localizedCaseInsensitiveContains("think") {
            // Older models reject the `think` switch; they don't think anyway.
            body["think"] = nil
            return try LLMPrompt.parseLines(try await chat(body))
        }
    }

    private func chat(_ body: [String: Any]) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.server(json?["error"] as? String ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let message = json?["message"] as? [String: Any], let content = message["content"] as? String else {
            throw TranslationEngineError.invalidResponse
        }
        return content
    }

    static func installedModels(baseURL: URL) async throws -> [OllamaModel] {
        var request = URLRequest(url: baseURL.appending(path: "api/tags"))
        request.timeoutInterval = 3
        let (data, _) = try await send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []
        return models.compactMap { ($0["name"] as? String).map(OllamaModel.init(name:)) }
            .sorted { ($0.isCloud ? 1 : 0, $0.name) < ($1.isCloud ? 1 : 0, $1.name) }
    }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost].contains(error.code) {
            throw TranslationEngineError.unavailable("Ollama no está en marcha. Abre Ollama.app.")
        }
    }
}

enum OllamaError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .server(message): "Ollama: \(message)"
        }
    }
}
