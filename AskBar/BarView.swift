//
//  BarView.swift
//  AskBar
//

import SwiftUI
import AppKit
import Combine

// MARK: - Conversation model

enum ConversationRole: Equatable {
    case user           // typed/dictated by the user
    case assistant      // AI reply to a user prompt
    case speaker        // line transcribed from the meeting audio
    case autoSuggestion // AI reply driven by the auto-trigger timer
}

struct ConversationMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ConversationRole
    var text: String
    var isStreaming: Bool
    var isError: Bool
    let timestamp: Date
}

// MARK: - BarView

struct BarView: View {
    var onClose: () -> Void = {}
    var onExpansionChange: (Bool) -> Void = { _ in }

    // MARK: Composer state
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedProvider: AIProvider = {
        if let raw = UserDefaults.standard.string(forKey: AIProvider.selectedProviderDefaultsKey),
           let p = AIProvider(rawValue: raw) {
            return p
        }
        return .claude
    }()
    @State private var currentModel: String = AIProvider.claude.selectedModel

    // MARK: Unified conversation
    @State private var messages: [ConversationMessage] = []
    @State private var streamTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Speech (mic) and meeting (call audio)
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var meetingModeCapture = MeetingAudioCapture.shared
    @State private var pulse: Bool = false

    // MARK: Auto-trigger / popover
    @State private var autoTriggerTask: Task<Void, Never>?
    @State private var lastAutoTriggerAt: Date?
    @State private var meetingPopoverOpen: Bool = false
    @State private var providerPopoverOpen: Bool = false

    @AppStorage("meetingAutoTriggerEnabled") private var autoTriggerEnabled: Bool = false
    @AppStorage("meetingAutoTriggerInterval") private var autoTriggerInterval: Double = 30.0
    @AppStorage("meetingAutoTriggerPrompt") private var autoTriggerPrompt: String = "Based on the meeting so far, what should I say next? Be brief and direct."
    @AppStorage("meetingAutoOnSilence") private var autoOnSilence: Bool = true

    // MARK: Layout
    private let collapsedHeight: CGFloat = 60
    private let expandedHeight: CGFloat = 480
    private let barWidth: CGFloat = 612

    private var isExpanded: Bool {
        isLoading || !messages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            composer
            if isExpanded {
                Divider().opacity(0.4)
                conversationView
            }
        }
        .frame(width: barWidth)
        .frame(maxHeight: expandedHeight)
        .background(barBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .onChange(of: isExpanded) { _, exp in onExpansionChange(exp) }
        .onChange(of: meetingModeCapture.isCapturing) { _, _ in restartAutoTriggerLoop() }
        .onChange(of: autoTriggerEnabled) { _, _ in restartAutoTriggerLoop() }
        .onChange(of: autoTriggerInterval) { _, _ in restartAutoTriggerLoop() }
        .onChange(of: speechManager.isRecording) { _, recording in
            // Free up the system speech recognizer for the user mic, then
            // hand it back to the meeting recognizer when dictation ends.
            // Without this the meeting "Them" transcript silently dies after
            // the first dictation pass.
            if recording {
                meetingModeCapture.pauseRecognizer()
            } else {
                // Small delay so the user-mic SFSpeechRecognizer fully tears
                // down before we grab the slot back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    meetingModeCapture.resumeRecognizer()
                }
            }
        }
        .onChange(of: speechManager.transcript) { _, v in
            if !v.isEmpty { inputText = v }
        }
        .onChange(of: selectedProvider) { _, p in
            UserDefaults.standard.set(p.rawValue, forKey: AIProvider.selectedProviderDefaultsKey)
            currentModel = p.selectedModel
        }
        .onAppear { currentModel = selectedProvider.selectedModel }
        .onReceive(meetingModeCapture.utterancePublisher) { handleIncomingUtterance($0) }
        .onReceive(NotificationCenter.default.publisher(for: .askBarStartVoiceSession)) { _ in
            startVoiceSession()
        }
        .background(escapeMonitor)
    }

    private var barBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(meetingModeCapture.isCapturing ? Color.green.opacity(0.45) : Color.white.opacity(0.08),
                        lineWidth: meetingModeCapture.isCapturing ? 1.2 : 1)
        }
    }

    private var escapeMonitor: some View {
        EscapeKeyHandler { onClose() }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            providerPill
            meetingPill

            TextField(composerPlaceholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit { sendUserPrompt() }

            primaryAction
        }
        .padding(.horizontal, 14)
        .frame(height: collapsedHeight)
    }

    private var composerPlaceholder: String {
        if speechManager.isRecording { return "Listening…" }
        if meetingModeCapture.isCapturing && messages.isEmpty {
            return "Meeting Mode is on — ask anything…"
        }
        return "Ask anything…"
    }

    // MARK: Provider pill

    private var providerPill: some View {
        Button {
            providerPopoverOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedProvider.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(selectedProvider.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $providerPopoverOpen, arrowEdge: .bottom) {
            providerPopover
        }
        .help("Provider: \(selectedProvider.displayName) · \(currentModel)")
    }

    private var providerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Provider")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(AIProvider.allCases) { provider in
                Button {
                    selectedProvider = provider
                    providerPopoverOpen = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: provider.iconName).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.displayName).font(.system(size: 12, weight: .medium))
                            Text(provider.selectedModel)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if provider == selectedProvider {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.top, 4)
            Text("Change models in Settings → API Keys")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .frame(width: 240)
    }

    // MARK: Meeting pill

    private var meetingPill: some View {
        Button {
            meetingPopoverOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(meetingDotColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                Image(systemName: "person.wave.2")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: meetingModeCapture.isCapturing)
                if let countdown = countdownText {
                    Text(countdown)
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(meetingModeCapture.isCapturing ? Color.green : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(meetingModeCapture.isCapturing
                               ? Color.green.opacity(0.15)
                               : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $meetingPopoverOpen, arrowEdge: .bottom) {
            meetingPopover
        }
        .help(meetingModeCapture.isCapturing
              ? "Meeting Mode is on. Click for options."
              : "Configure Meeting Mode")
    }

    private var meetingDotColor: Color {
        if !meetingModeCapture.lastError.isEmpty { return .red }
        if meetingModeCapture.isCapturing { return .green }
        return .gray
    }

    private var countdownText: String? {
        guard meetingModeCapture.isCapturing,
              autoTriggerEnabled,
              let last = lastAutoTriggerAt else { return nil }
        let elapsed = Date().timeIntervalSince(last)
        let interval = max(1.0, autoTriggerInterval)
        let remaining = max(0, Int(interval - elapsed))
        return "\(remaining)s"
    }

    private var meetingPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Meeting Mode")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if meetingModeCapture.isCapturing {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green))
                }
            }

            Toggle(isOn: Binding(
                get: { meetingModeCapture.isCapturing },
                set: { newValue in
                    Task {
                        if newValue { await meetingModeCapture.startCapture() }
                        else { await meetingModeCapture.stopCapture() }
                    }
                }
            )) {
                Text("Listen to call audio")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            Toggle(isOn: $autoOnSilence) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-respond to each utterance")
                        .font(.system(size: 12))
                    Text("Reply each time the speaker pauses")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $autoTriggerEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-suggest on a timer")
                            .font(.system(size: 12))
                        Text("Send the suggestion prompt every N seconds")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if autoTriggerEnabled {
                    HStack(spacing: 6) {
                        Text("Every").font(.system(size: 11))
                        TextField("30", value: $autoTriggerInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                            .controlSize(.small)
                        Text("seconds (min 5)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }

            Divider()

            Button {
                meetingPopoverOpen = false
                sendSuggestion(isAuto: false)
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Suggest a reply now")
                    Spacer()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(!meetingModeCapture.isCapturing || isLoading)
            .opacity(meetingModeCapture.isCapturing && !isLoading ? 1 : 0.5)

            if !meetingModeCapture.lastError.isEmpty {
                Text(meetingModeCapture.lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Primary action (mic ↔ send morphing)

    private var primaryAction: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInput = !trimmed.isEmpty
        return Button {
            if hasInput {
                sendUserPrompt()
            } else {
                if !speechManager.isRecording {
                    speechManager.baseText = inputText
                }
                speechManager.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(primaryActionFill(hasInput: hasInput))
                    .frame(width: 32, height: 32)
                Image(systemName: primaryActionIcon(hasInput: hasInput))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryActionForeground(hasInput: hasInput))
                    .scaleEffect(speechManager.isRecording && pulse ? 1.15 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .keyboardShortcut(.return, modifiers: [])
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        let trimmedNow = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedNow.isEmpty && !isLoading {
                            sendUserPrompt()
                        }
                    }
                }
            }
        }
        .help(hasInput ? "Send (↩)" : (speechManager.isRecording ? "Stop dictation" : "Start dictation"))
    }

    private func primaryActionIcon(hasInput: Bool) -> String {
        if hasInput { return "arrow.up" }
        return speechManager.isRecording ? "mic.fill" : "mic"
    }

    private func primaryActionFill(hasInput: Bool) -> Color {
        if hasInput { return Color.accentColor }
        if speechManager.isRecording { return Color.red }
        return Color.primary.opacity(0.12)
    }

    private func primaryActionForeground(hasInput: Bool) -> Color {
        if hasInput || speechManager.isRecording { return Color.white }
        return Color.primary
    }

    // MARK: - Conversation thread

    private var conversationView: some View {
        VStack(spacing: 0) {
            conversationHeader
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            messageBubble(message).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("threadBottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("threadBottom", anchor: .bottom) }
                }
                .onChange(of: messages.last?.text) { _, _ in
                    withAnimation { proxy.scrollTo("threadBottom", anchor: .bottom) }
                }
            }
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: 8) {
            Text("\(messages.count) message\(messages.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                copyThread()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty)
            .help("Copy whole conversation")
            Button {
                clearThread()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty)
            .help("Clear conversation")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func messageBubble(_ msg: ConversationMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }

        case .assistant, .autoSuggestion:
            HStack(alignment: .top, spacing: 8) {
                roleTag(msg.role == .autoSuggestion ? "AUTO" : "AI",
                        color: msg.isError ? .red : .accentColor)
                Group {
                    if msg.text.isEmpty && msg.isStreaming {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.5)
                            Text("Thinking…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(msg.text)
                            .font(.system(size: 13))
                            .foregroundStyle(msg.isError ? Color.red : Color(NSColor.labelColor))
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

        case .speaker:
            HStack(alignment: .top, spacing: 8) {
                roleTag("THEM", color: .green)
                Text(msg.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .italic()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
    }

    private func roleTag(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.85)))
    }

    // MARK: - Sending

    private func sendUserPrompt() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isLoading else { return }
        inputText = ""
        speechManager.baseText = ""
        appendUserAndStreamReply(prompt: prompt, role: .assistant, hideUserBubble: false)
    }

    private func sendSuggestion(isAuto: Bool) {
        let prompt = autoTriggerPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if isAuto { lastAutoTriggerAt = Date() }
        appendUserAndStreamReply(prompt: prompt,
                                 role: isAuto ? .autoSuggestion : .assistant,
                                 hideUserBubble: true)
    }

    private func appendUserAndStreamReply(prompt: String,
                                          role: ConversationRole,
                                          hideUserBubble: Bool) {
        if !hideUserBubble {
            messages.append(ConversationMessage(role: .user,
                                                text: prompt,
                                                isStreaming: false,
                                                isError: false,
                                                timestamp: Date()))
        }
        let aiMsg = ConversationMessage(role: role,
                                        text: "",
                                        isStreaming: true,
                                        isError: false,
                                        timestamp: Date())
        messages.append(aiMsg)
        let id = aiMsg.id
        let provider = selectedProvider
        let meetingContext = meetingModeCapture.isCapturing ? meetingModeCapture.getContextForPrompt() : ""
        let systemPrompt = buildSystemPrompt(meetingContext: meetingContext)

        isLoading = true
        let task = Task { @MainActor in
            do {
                let service = AIServiceFactory.make(for: provider)
                let stream = try await service.send(prompt: prompt, systemPrompt: systemPrompt)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let idx = messages.firstIndex(where: { $0.id == id }) {
                        messages[idx].text += chunk
                    }
                }
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages[idx].isStreaming = false
                }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages[idx].text = "Error: \(error.localizedDescription)"
                    messages[idx].isError = true
                    messages[idx].isStreaming = false
                }
            }
            isLoading = false
            streamTasks[id] = nil
        }
        streamTasks[id] = task
    }

    // MARK: - Per-utterance handling

    private func handleIncomingUtterance(_ utterance: String) {
        guard meetingModeCapture.isCapturing else { return }
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Always append a speaker bubble so the user sees what was heard.
        messages.append(ConversationMessage(role: .speaker,
                                            text: trimmed,
                                            isStreaming: false,
                                            isError: false,
                                            timestamp: Date()))

        // Only auto-respond when the toggle is on.
        guard autoOnSilence else { return }

        let aiMsg = ConversationMessage(role: .assistant,
                                        text: "",
                                        isStreaming: true,
                                        isError: false,
                                        timestamp: Date())
        messages.append(aiMsg)
        let id = aiMsg.id
        let provider = selectedProvider
        let prompt = "The other person on the call just said: \"\(trimmed)\"\n\nGive me a brief, direct reply I can say back."
        let systemPrompt = buildSystemPrompt(meetingContext: meetingModeCapture.getContextForPrompt())

        let task = Task { @MainActor in
            do {
                let service = AIServiceFactory.make(for: provider)
                let stream = try await service.send(prompt: prompt, systemPrompt: systemPrompt)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let idx = messages.firstIndex(where: { $0.id == id }) {
                        messages[idx].text += chunk
                    }
                }
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages[idx].isStreaming = false
                }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages[idx].text = "Error: \(error.localizedDescription)"
                    messages[idx].isError = true
                    messages[idx].isStreaming = false
                }
            }
            streamTasks[id] = nil
        }
        streamTasks[id] = task
    }

    private func clearThread() {
        for (_, task) in streamTasks { task.cancel() }
        streamTasks.removeAll()
        messages.removeAll()
        isLoading = false
    }

    private func copyThread() {
        let text = messages.map { msg -> String in
            switch msg.role {
            case .user:           return "You: \(msg.text)"
            case .assistant:      return "AI: \(msg.text)"
            case .autoSuggestion: return "AI (auto): \(msg.text)"
            case .speaker:        return "Them: \(msg.text)"
            }
        }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Voice session

    private func startVoiceSession() {
        clearThread()
        inputText = ""
        speechManager.baseText = ""
        if speechManager.isRecording {
            speechManager.stopRecording()
        }
        speechManager.toggle()
    }

    // MARK: - Auto-trigger loop

    private func restartAutoTriggerLoop() {
        autoTriggerTask?.cancel()
        autoTriggerTask = nil
        guard meetingModeCapture.isCapturing, autoTriggerEnabled else { return }
        let interval = max(5.0, autoTriggerInterval)
        autoTriggerTask = Task { @MainActor in
            while !Task.isCancelled,
                  meetingModeCapture.isCapturing,
                  autoTriggerEnabled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                guard meetingModeCapture.isCapturing, autoTriggerEnabled else { break }
                let transcript = meetingModeCapture.rollingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty, !isLoading else { continue }
                sendSuggestion(isAuto: true)
            }
        }
    }
}

// MARK: - ESC key local monitor wrapper

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
