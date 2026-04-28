//
//  SettingsView.swift
//  AskBar
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AIProvider.selectedProviderDefaultsKey) private var selectedProviderRaw: String = AIProvider.claude.rawValue
    @AppStorage("micAutoStop") private var micAutoStop: Bool = true
    @AppStorage("micAutoSendOnStop") private var micAutoSendOnStop: Bool = true
    @AppStorage("voiceSessionShortcutEnabled") private var voiceSessionShortcutEnabled: Bool = true

    private var selectedProvider: Binding<AIProvider> {
        Binding(
            get: { AIProvider(rawValue: selectedProviderRaw) ?? .claude },
            set: { selectedProviderRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            keysTab
                .tabItem { Label("API Keys", systemImage: "key.fill") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 520)
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Section("Default Provider") {
                Picker("Provider", selection: selectedProvider) {
                    ForEach(AIProvider.allCases) { p in
                        Label(p.displayName, systemImage: p.iconName).tag(p)
                    }
                }
                .pickerStyle(.menu)
            }
            Section("Hotkey") {
                HStack {
                    Text("Toggle AskBar")
                    Spacer()
                    Text("⌘⇧Space")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: $voiceSessionShortcutEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable voice session shortcut")
                        Text("Use ⌘⇧V to open AskBar, clear session, and start recording")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Microphone") {
                Toggle(isOn: $micAutoStop) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-stop microphone on silence")
                        Text("Stops recording automatically after ~1.5 seconds of silence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $micAutoSendOnStop) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-send when microphone stops")
                        Text("When recording ends, immediately send the transcribed prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var keysTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(AIProvider.allCases) { provider in
                    APIKeyRow(provider: provider)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("AskBar")
                .font(.title.bold())
            Text("Version 1.0")
                .foregroundStyle(.secondary)
            Text("A native macOS menu-bar AI assistant.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("GitHub", destination: URL(string: "https://github.com/")!)
                .padding(.top, 6)
            Spacer()
        }
        .padding(.top, 24)
    }
}

private struct APIKeyRow: View {
    let provider: AIProvider
    @State private var key: String = ""
    @State private var selectedModel: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: provider.iconName)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                SecureField("API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: key) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: provider.apiKeyDefaultsKey)
                    }
                Picker("Model", selection: $selectedModel) {
                    ForEach(provider.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModel) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: provider.selectedModelDefaultsKey)
                }
            }
            if !key.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.top, 2)
            } else {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04))
        )
        .onAppear {
            key = UserDefaults.standard.string(forKey: provider.apiKeyDefaultsKey) ?? ""
            let stored = UserDefaults.standard.string(forKey: provider.selectedModelDefaultsKey) ?? ""
            if provider.availableModels.contains(stored) {
                selectedModel = stored
            } else {
                selectedModel = provider.defaultModel
            }
        }
    }
}
