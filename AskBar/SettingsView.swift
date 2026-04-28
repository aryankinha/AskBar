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
    @AppStorage("meetingBufferDuration") private var meetingBufferDuration: Double = 60.0
    @AppStorage("meetingAutoTriggerEnabled") private var meetingAutoTriggerEnabled: Bool = false
    @AppStorage("meetingAutoTriggerInterval") private var meetingAutoTriggerInterval: Double = 30.0
    @AppStorage("meetingAutoTriggerPrompt") private var meetingAutoTriggerPrompt: String = "Based on the meeting so far, what should I say next? Be brief and direct."
    @AppStorage("meetingAutoOnSilence") private var meetingAutoOnSilence: Bool = true
    @StateObject private var meetingCapture = MeetingAudioCapture.shared

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
            meetingTab
                .tabItem { Label("Meeting", systemImage: "person.wave.2") }
            keysTab
                .tabItem { Label("API Keys", systemImage: "key.fill") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 580)
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

    private var meetingTab: some View {
        Form {
            Section("Permissions") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: meetingCapture.permissionDenied ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .foregroundStyle(meetingCapture.permissionDenied ? Color.orange : Color.green)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meetingCapture.permissionDenied
                             ? "Screen Recording permission required"
                             : "Screen Recording permission granted (or not yet requested)")
                            .font(.system(size: 12, weight: .medium))
                        Text("AskBar uses macOS Screen & System Audio Recording to listen to call audio. No screen pixels are read.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Screen Recording Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            Section("Capture") {
                Toggle(isOn: Binding(
                    get: { meetingCapture.isCapturing },
                    set: { newValue in
                        Task {
                            if newValue { await meetingCapture.startCapture() }
                            else { await meetingCapture.stopCapture() }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listen to meeting audio")
                        Text("Captures audio from Zoom, Meet, Teams, Webex, Safari, Chrome.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Rolling buffer (context window)", selection: $meetingBufferDuration) {
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                    Text("90 seconds").tag(90.0)
                    Text("120 seconds").tag(120.0)
                }
                .pickerStyle(.menu)
                if meetingCapture.isCapturing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live transcript preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(meetingCapture.rollingTranscript.suffix(200).description)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                            )
                    }
                }
                if !meetingCapture.lastError.isEmpty {
                    Text(meetingCapture.lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Auto-respond") {
                Toggle(isOn: $meetingAutoOnSilence) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reply to each utterance")
                        Text("Whenever the speaker pauses, the AI replies inline in the conversation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Auto-suggest on a timer") {
                Toggle(isOn: $meetingAutoTriggerEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggest a reply on a fixed interval")
                        Text("Sends the prompt below every N seconds while capturing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Interval (seconds)")
                    Spacer()
                    TextField("30", value: $meetingAutoTriggerInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Minimum 5 seconds. Lower values use more API credits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt sent on each trigger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $meetingAutoTriggerPrompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 60, maxHeight: 90)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                        )
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
