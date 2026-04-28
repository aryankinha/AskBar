//
//  ClaudeService.swift
//  AskBar
//

import Foundation

struct ClaudeService: AIServiceProtocol {
    func send(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let key = AIServiceFactory.apiKey(for: .claude) else {
            throw AIServiceError.missingAPIKey(provider: "Claude")
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIServiceError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": AIProvider.claude.selectedModel,
            "max_tokens": 1024,
            "stream": true,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]]
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
                           let type = obj["type"] as? String,
                           type == "content_block_delta",
                           let delta = obj["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
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
