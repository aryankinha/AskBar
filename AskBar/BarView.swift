//
//  BarView.swift
//  AskBar
//

import SwiftUI
import AppKit

struct BarView: View {
    var onClose: () -> Void = {}
    var onExpansionChange: (Bool) -> Void = { _ in }

    @State private var inputText: String = ""
    @State private var responseText: String = ""
    @State private var isLoading: Bool = false
    @State private var isError: Bool = false
    @State private var selectedProvider: AIProvider = {
        if let raw = UserDefaults.standard.string(forKey: AIProvider.selectedProviderDefaultsKey),
           let p = AIProvider(rawValue: raw) {
            return p
        }
        return .claude
    }()
    @StateObject private var speechManager = SpeechManager()
    @State private var pulse: Bool = false
    @State private var streamingTask: Task<Void, Never>?
    @State private var currentModel: String = AIProvider.claude.selectedModel

    private let collapsedHeight: CGFloat = 56
    private let responseHeight: CGFloat = 280
    private let maxExpandedHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if isLoading || !responseText.isEmpty {
                responseSection
            }
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 8)
        .frame(minWidth: 620, idealWidth: 620, maxWidth: 720)
        .frame(maxHeight: maxExpandedHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: responseText)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isLoading)
        .onChange(of: speechManager.transcript) { _, newValue in
            if !newValue.isEmpty {
                inputText = newValue
            }
        }
        .onChange(of: selectedProvider) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: AIProvider.selectedProviderDefaultsKey)
            currentModel = newValue.selectedModel
        }
        .onChange(of: responseText) { _, newValue in
            onExpansionChange(isLoading || !newValue.isEmpty)
        }
        .onChange(of: isLoading) { _, newValue in
            onExpansionChange(newValue || !responseText.isEmpty)
        }
        .onAppear {
            currentModel = selectedProvider.selectedModel
        }
        .onReceive(NotificationCenter.default.publisher(for: .askBarStartVoiceSession)) { _ in
            startVoiceSession()
        }
        .background(escapeMonitor)
    }

    // ESC key handler via NSEvent local monitor
    private var escapeMonitor: some View {
        EscapeKeyHandler {
            onClose()
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            // Provider picker
            Menu {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        selectedProvider = provider
                    } label: {
                        Label(provider.displayName, systemImage: provider.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedProvider.iconName)
                        .font(.system(size: 14, weight: .medium))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedProvider.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Text(currentModel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Text field
            TextField("Ask anything…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit {
                    sendQuery()
                }

            // Mic button
            Button {
                if !speechManager.isRecording {
                    // Capture whatever the user already typed so speech is appended.
                    speechManager.baseText = inputText
                }
                speechManager.toggle()
            } label: {
                Image(systemName: speechManager.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(speechManager.isRecording ? Color.red : Color.primary)
                    .scaleEffect(speechManager.isRecording && pulse ? 1.15 : 1.0)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .onChange(of: speechManager.isRecording) { oldValue, recording in
                if recording {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    pulse = false
                }

                // Auto-submit the prompt as soon as recording ends (default ON).
                if oldValue && !recording {
                    let autoSend = (UserDefaults.standard.object(forKey: "micAutoSendOnStop") as? Bool) ?? true
                    if autoSend && !isLoading {
                        // Wait briefly for the speech recognizer to flush its
                        // final transcript into `inputText` via the
                        // transcript->inputText binding before submitting.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !isLoading {
                                sendQuery()
                            }
                        }
                    }
                }
            }

            // Send button
            Button {
                sendQuery()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isLoading)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 14)
        .frame(height: collapsedHeight)
    }

    private var responseSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
                    .padding(.horizontal, 8)

                if isLoading && responseText.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Thinking…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .frame(height: responseHeight)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(responseText)
                            .font(.system(size: 14))
                            .foregroundColor(isError ? Color.red : Color(NSColor.labelColor))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(height: responseHeight)
                    .padding(.horizontal, 8)
                }
            }
            .frame(height: responseHeight)

            HStack {
                Text("\(responseText.count) chars")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(responseText, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .disabled(responseText.isEmpty)

                Button(action: {
                    responseText = ""
                    inputText = ""
                    speechManager.baseText = ""
                }) {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 6)
        }
    }

    // MARK: - Send query

    private func sendQuery() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        streamingTask?.cancel()
        responseText = ""
        isError = false
        isLoading = true

        // Clear the input now that the prompt has been captured. This is the
        // ONLY place (alongside the Clear button) where inputText/baseText
        // are wiped — never on mic stop.
        inputText = ""
        speechManager.baseText = ""

        let provider = selectedProvider
        streamingTask = Task { @MainActor in
            do {
                let service = AIServiceFactory.make(for: provider)
                let stream = try await service.send(prompt: prompt)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    responseText += chunk
                }
                isLoading = false
            } catch {
                isError = true
                responseText = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func startVoiceSession() {
        streamingTask?.cancel()
        responseText = ""
        isError = false
        isLoading = false
        inputText = ""
        speechManager.baseText = ""

        if speechManager.isRecording {
            speechManager.stopRecording()
        }

        speechManager.baseText = inputText
        speechManager.toggle()
    }
}

// ESC key local monitor wrapper
struct EscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlingView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? KeyHandlingView {
            v.onEscape = onEscape
        }
    }

    final class KeyHandlingView: NSView {
        var onEscape: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if event.keyCode == 53 { // ESC
                        self?.onEscape?()
                        return nil
                    }
                    return event
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
