//
//  AIService.swift
//  AskBar
//

import Foundation

enum AIServiceError: LocalizedError {
    case missingAPIKey(provider: String)
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): return "Missing API key for \(p). Open Settings to add one."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let status, let body): return "HTTP \(status): \(body)"
        }
    }
}

protocol AIServiceProtocol {
    func send(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error>
}

extension AIServiceProtocol {
    func send(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        try await send(prompt: prompt, systemPrompt: askBarSystemPrompt)
    }
}

enum AIServiceFactory {
    static func make(for provider: AIProvider) -> AIServiceProtocol {
        switch provider {
        case .claude: return ClaudeService()
        case .openai: return OpenAIService()
        case .groq: return GroqService()
        case .gemini: return GeminiService()
        case .openrouter: return OpenRouterService()
        case .nvidia: return NvidiaService()
        }
    }

    static func apiKey(for provider: AIProvider) -> String? {
        let key = UserDefaults.standard.string(forKey: provider.apiKeyDefaultsKey)
        guard let key = key, !key.isEmpty else { return nil }
        return key
    }
}

// Helper: read a streamed HTTP body as lines
extension URLSession {
    func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (bytes, response) = try await self.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            // Drain body for error message
            var body = ""
            for try await line in bytes.lines {
                body += line + "\n"
                if body.count > 2000 { break }
            }
            throw AIServiceError.httpError(status: http.statusCode, body: body)
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, http)
    }
}
