//
//  GeminiService.swift
//  AskBar
//

import Foundation

struct GeminiService: AIServiceProtocol {
    func send(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let key = AIServiceFactory.apiKey(for: .gemini) else {
            throw AIServiceError.missingAPIKey(provider: "Gemini")
        }
        let model = AIProvider.gemini.selectedModel
        // Use SSE-style streaming
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(key)") else {
            throw AIServiceError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": askBarSystemPrompt]]
            ],
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (lineStream, _) = try await URLSession.shared.streamLines(for: req)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lineStream {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if let data = payload.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let candidates = obj["candidates"] as? [[String: Any]],
                           let first = candidates.first,
                           let content = first["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]] {
                            for part in parts {
                                if let text = part["text"] as? String {
                                    continuation.yield(text)
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
