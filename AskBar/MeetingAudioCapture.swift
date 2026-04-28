//
//  MeetingAudioCapture.swift
//  AskBar
//
//  Captures audio from running meeting/browser apps via ScreenCaptureKit,
//  transcribes it with SFSpeechRecognizer, and exposes a rolling N-second
//  transcript that AskBar can inject into AI prompts as context.
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import Speech
import Combine
import CoreMedia

@MainActor
final class MeetingAudioCapture: NSObject, ObservableObject {

    static let shared = MeetingAudioCapture()

    // MARK: - Published state
    @Published var isCapturing: Bool = false
    @Published var rollingTranscript: String = ""
    @Published var permissionDenied: Bool = false
    @Published var lastError: String = ""

    /// Fires once per finalized utterance (i.e. each time the speaker pauses
    /// long enough that SFSpeechRecognizer marks the result as final). Used
    /// by the UI to drive the chat-style auto-send.
    let utterancePublisher = PassthroughSubject<String, Never>()

    // MARK: - Private
    private var stream: SCStream?
    private var speechRecognizer: SFSpeechRecognizer?
    fileprivate var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Debounce state for detecting utterance boundaries from partial results.
    private var lastPartialText: String = ""
    private var lastPartialChangeAt: Date = .distantPast
    private var emittedPrefixForCurrentRequest: String = ""
    private var debounceTimer: Timer?
    private var requestStartedAt: Date = .distantPast
    private let utteranceSilenceThreshold: TimeInterval = 1.5
    private let minUtteranceCharacters: Int = 4
    private let stuckRecognizerTimeout: TimeInterval = 8.0

    // Rolling buffer of (timestamp, text) tuples.
    private var transcriptBuffer: [(date: Date, text: String)] = []

    /// User-configurable rolling window length (seconds).
    private var bufferDuration: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "meetingBufferDuration")
        return stored > 0 ? stored : 60.0
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        // SCShareableContent.current throws if the user hasn't granted
        // Screen Recording permission. We use it as our gate.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            permissionDenied = false
            return true
        } catch {
            permissionDenied = true
            lastError = "Screen recording permission required. Grant it in System Settings > Privacy & Security > Screen Recording."
            return false
        }
    }

    // MARK: - Start / stop

    func startCapture(targetAppBundleIDs: [String] = [
        "us.zoom.xos",                 // Zoom
        "com.google.Chrome",           // Chrome (Google Meet, etc.)
        "com.apple.Safari",            // Safari
        "com.microsoft.teams2",        // Microsoft Teams
        "com.webex.meetingmanager"     // Webex
    ]) async {
        guard !isCapturing else { return }

        let hasPermission = await requestPermission()
        guard hasPermission else { return }

        // Speech recognition authorization.
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else {
            lastError = "Speech recognition permission denied for Meeting Mode."
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )

            guard let display = content.displays.first else {
                lastError = "No display found for audio capture."
                return
            }

            let targetApps = content.applications.filter { app in
                targetAppBundleIDs.contains(app.bundleIdentifier)
            }

            let filter: SCContentFilter
            if targetApps.isEmpty {
                // Fallback: capture everything on the display (audio only).
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else {
                filter = SCContentFilter(
                    display: display,
                    including: targetApps,
                    exceptingWindows: []
                )
            }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16000
            config.channelCount = 1

            setupSpeechRecognition()

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: DispatchQueue(label: "askbar.meeting.audio")
            )
            try await newStream.startCapture()

            self.stream = newStream
            isCapturing = true
            lastError = ""

        } catch {
            lastError = "Capture failed: \(error.localizedDescription)"
            isCapturing = false
        }
    }

    func stopCapture() async {
        guard isCapturing else { return }
        if let stream = stream {
            try? await stream.stopCapture()
        }
        stream = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        lastPartialText = ""
        emittedPrefixForCurrentRequest = ""
        isCapturing = false
    }

    func toggle() async {
        if isCapturing {
            await stopCapture()
        } else {
            await startCapture()
        }
    }

    // MARK: - Speech recognition

    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.defaultTaskHint = .dictation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request
        lastPartialText = ""
        emittedPrefixForCurrentRequest = ""
        lastPartialChangeAt = Date()
        requestStartedAt = Date()

        // Debounce timer drives utterance-boundary detection from partial
        // results, because SFSpeechRecognizer rarely emits isFinal on a
        // continuous meeting audio stream.
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let weakSelf = self else { return }
            Task { @MainActor [weak weakSelf] in
                weakSelf?.checkForUtteranceBoundary()
            }
        }
        if let timer = debounceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { @MainActor in
                    if isFinal {
                        // Flush whatever new text we haven't emitted yet.
                        self.flushUtterance(currentText: text, restart: self.isCapturing)
                    } else {
                        if text != self.lastPartialText {
                            self.lastPartialText = text
                            self.lastPartialChangeAt = Date()
                        }
                        // Show partial in the rolling buffer too so the live
                        // preview feels responsive.
                        self.rollingTranscript = self.bufferText(appendingPartial: text)
                    }
                }
            }
            if let error = error {
                let nsError = error as NSError
                let isBenign = (nsError.code == 301 || nsError.code == 203 || nsError.code == 216 || nsError.code == 1110)
                Task { @MainActor in
                    if !isBenign {
                        self.lastError = "Speech error: \(error.localizedDescription)"
                    }
                    // The recognition task is now dead. If we're still
                    // capturing (e.g. the user mic just preempted us), the
                    // SCStream keeps appending PCM to a stale request and
                    // produces nothing. Restart the recognizer so transcription
                    // resumes automatically without requiring a Meeting Mode
                    // toggle.
                    guard self.isCapturing else { return }
                    self.debounceTimer?.invalidate()
                    self.debounceTimer = nil
                    self.recognitionRequest?.endAudio()
                    self.recognitionTask?.cancel()
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    // Small delay so we don't immediately collide with whatever
                    // preempted us (the system mic recognition task).
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if self.isCapturing {
                        self.setupSpeechRecognition()
                    }
                }
            }
        }
    }

    private func checkForUtteranceBoundary() {
        guard isCapturing else { return }

        // Recovery: if the recognizer has produced nothing at all for several
        // seconds since this request started, it's almost certainly stuck
        // (e.g. preempted by the user mic SFSpeechRecognizer). Restart.
        if lastPartialText.isEmpty,
           Date().timeIntervalSince(requestStartedAt) >= stuckRecognizerTimeout {
            debounceTimer?.invalidate()
            debounceTimer = nil
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            setupSpeechRecognition()
            return
        }

        let current = lastPartialText
        let newText = current.dropFirst(emittedPrefixForCurrentRequest.count)
        let trimmedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNew.count >= minUtteranceCharacters else { return }
        // Only flush if the partial hasn't grown in `utteranceSilenceThreshold` seconds.
        guard Date().timeIntervalSince(lastPartialChangeAt) >= utteranceSilenceThreshold else { return }

        // Force-finalize: ending audio on the request triggers an isFinal
        // callback which calls flushUtterance(restart: true). We just need to
        // emit what we have right now in case the recognizer drops it.
        flushUtterance(currentText: current, restart: true)
    }

    private func flushUtterance(currentText: String, restart: Bool) {
        let newPortion = String(currentText.dropFirst(emittedPrefixForCurrentRequest.count))
        let trimmed = newPortion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appendToBuffer(trimmed)
            utterancePublisher.send(trimmed)
        }
        emittedPrefixForCurrentRequest = currentText

        guard restart, isCapturing else { return }

        // Tear down current request/task and start fresh so the partial
        // counter resets and we don't keep re-emitting the same prefix.
        debounceTimer?.invalidate()
        debounceTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        setupSpeechRecognition()
    }

    // MARK: - Rolling buffer

    private func appendToBuffer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        transcriptBuffer.append((date: now, text: trimmed))
        prune(now: now)
        rollingTranscript = transcriptBuffer.map { $0.text }.joined(separator: " ")
    }

    private func prune(now: Date) {
        let cutoff = bufferDuration
        transcriptBuffer.removeAll { now.timeIntervalSince($0.date) > cutoff }
    }

    private func bufferText(appendingPartial partial: String) -> String {
        prune(now: Date())
        let finalized = transcriptBuffer.map { $0.text }.joined(separator: " ")
        let trimmedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalized.isEmpty { return trimmedPartial }
        if trimmedPartial.isEmpty { return finalized }
        return finalized + " " + trimmedPartial
    }

    // MARK: - Prompt context

    func getContextForPrompt() -> String {
        let snapshot = rollingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snapshot.isEmpty else { return "" }
        return """
        [Meeting context — last \(Int(bufferDuration)) seconds of conversation:]
        \(snapshot)
        [End of meeting context]
        """
    }
}

// MARK: - SCStreamDelegate

extension MeetingAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            MeetingAudioCapture.shared.isCapturing = false
            MeetingAudioCapture.shared.lastError = "Stream stopped: \(error.localizedDescription)"
        }
    }
}

// MARK: - SCStreamOutput

extension MeetingAudioCapture: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let pcmBuffer = sampleBuffer.askBarPCMBuffer() else { return }
        Task { @MainActor in
            MeetingAudioCapture.shared.recognitionRequest?.append(pcmBuffer)
        }
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

private extension CMSampleBuffer {
    nonisolated func askBarPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frameCount = UInt32(CMSampleBufferGetNumSamples(self))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else { return nil }
        var dataPointer: UnsafeMutablePointer<Int8>?
        var totalLength = 0
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
            return nil
        }

        if let channelData = buffer.int16ChannelData {
            dataPointer.withMemoryRebound(to: Int16.self, capacity: Int(frameCount)) { source in
                channelData[0].update(from: source, count: Int(frameCount))
            }
        } else if let channelData = buffer.floatChannelData {
            dataPointer.withMemoryRebound(to: Float.self, capacity: Int(frameCount)) { source in
                channelData[0].update(from: source, count: Int(frameCount))
            }
        } else {
            return nil
        }

        return buffer
    }
}
