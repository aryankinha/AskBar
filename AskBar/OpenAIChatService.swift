//
//  OpenAIChatService.swift
//  AskBar
//
//  Generic OpenAI-compatible chat completion streaming used by OpenAI, Groq, OpenRouter.
//

import Foundation

struct OpenAICompatibleService {
    let endpoint: URL
    let apiKey: String
    let model: String
    let extraHeaders: [String: String]

    func stream(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
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
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        if let data = payload.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = obj["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
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

struct OpenAIService: AIServiceProtocol {
    func send(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let key = AIServiceFactory.apiKey(for: .openai) else {
            throw AIServiceError.missingAPIKey(provider: "OpenAI")
        }
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIServiceError.invalidResponse
        }
        let svc = OpenAICompatibleService(endpoint: url, apiKey: key,
                                          model: AIProvider.openai.selectedModel,
                                          extraHeaders: [:])
        return try await svc.stream(prompt: prompt, systemPrompt: systemPrompt)
    }
}

struct GroqService: AIServiceProtocol {
    func send(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let key = AIServiceFactory.apiKey(for: .groq) else {
            throw AIServiceError.missingAPIKey(provider: "Groq")
        }
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw AIServiceError.invalidResponse
        }
        let svc = OpenAICompatibleService(endpoint: url, apiKey: key,
                                          model: AIProvider.groq.selectedModel,
                                          extraHeaders: [:])
        return try await svc.stream(prompt: prompt, systemPrompt: systemPrompt)
    }
}

struct OpenRouterService: AIServiceProtocol {
    func send(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let key = AIServiceFactory.apiKey(for: .openrouter) else {
            throw AIServiceError.missingAPIKey(provider: "OpenRouter")
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw AIServiceError.invalidResponse
        }
        let svc = OpenAICompatibleService(endpoint: url, apiKey: key,
                                          model: AIProvider.openrouter.selectedModel,
                                          extraHeaders: [
                                            "HTTP-Referer": "https://askbar.app",
                                            "X-Title": "AskBar"
                                          ])
        return try await svc.stream(prompt: prompt, systemPrompt: systemPrompt)
    }
}
