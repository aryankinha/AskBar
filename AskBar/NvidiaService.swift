//
//  NvidiaService.swift
//  AskBar
//
//  NVIDIA exposes an OpenAI-compatible chat-completions endpoint.
//

import Foundation

struct NvidiaService: AIServiceProtocol {
    func send(prompt: String, systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let key = AIServiceFactory.apiKey(for: .nvidia) else {
            throw AIServiceError.missingAPIKey(provider: "NVIDIA")
        }
        guard let url = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions") else {
            throw AIServiceError.invalidResponse
        }
        let svc = OpenAICompatibleService(endpoint: url,
                                          apiKey: key,
                                          model: AIProvider.nvidia.selectedModel,
                                          extraHeaders: [:])
        return try await svc.stream(prompt: prompt, systemPrompt: systemPrompt)
    }
}
