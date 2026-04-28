//
//  AIProvider.swift
//  AskBar
//

import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case openai
    case groq
    case gemini
    case openrouter
    case nvidia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .groq: return "Groq"
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        case .nvidia: return "NVIDIA"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "sparkles"
        case .openai: return "bubble.left.and.bubble.right.fill"
        case .groq: return "bolt.fill"
        case .gemini: return "diamond.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .nvidia: return "cpu"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-4-5"
        case .openai: return "gpt-4o"
        case .groq: return "llama-3.3-70b-versatile"
        case .gemini: return "gemini-2.0-flash"
        case .openrouter: return "mistralai/mistral-7b-instruct"
        case .nvidia: return "meta/llama-3.3-70b-instruct"
        }
    }

    var availableModels: [String] {
        switch self {
        case .claude:
            return ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"]
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768", "gemma2-9b-it"]
        case .gemini:
            return ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .openrouter:
            return ["mistralai/mistral-7b-instruct", "meta-llama/llama-3.3-70b-instruct", "google/gemma-3-27b-it", "deepseek/deepseek-r1"]
        case .nvidia:
            return ["meta/llama-3.3-70b-instruct", "nvidia/llama-3.1-nemotron-70b-instruct", "mistralai/mistral-large", "google/gemma-3-27b-it"]
        }
    }

    var apiKeyDefaultsKey: String {
        "apiKey_\(rawValue)"
    }

    var selectedModelDefaultsKey: String {
        "selectedModel_\(rawValue)"
    }

    /// Currently chosen model for this provider, persisted in `UserDefaults`,
    /// falling back to `defaultModel` when none has been selected.
    var selectedModel: String {
        let stored = UserDefaults.standard.string(forKey: selectedModelDefaultsKey)
        if let stored = stored, !stored.isEmpty {
            return stored
        }
        return defaultModel
    }

    static let selectedProviderDefaultsKey = "selectedProvider"
}
