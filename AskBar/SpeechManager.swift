//
//  SpeechManager.swift
//  AskBar
//

import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechManager: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    /// Caller sets this to the current text-field value before invoking
    /// `startRecording()`/`toggle()`. Recognized speech is appended to it
    /// instead of replacing whatever the user already typed.
    var baseText: String = ""

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    func toggle() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer not available"
            return
        }

        // Request speech permission
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else {
            errorMessage = "Speech recognition permission denied"
            return
        }

        // Request mic permission (macOS uses AVCaptureDevice for mic)
        let micAuth: Bool = await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            default:
                cont.resume(returning: false)
            }
        }
        guard micAuth else {
            errorMessage = "Microphone permission denied"
            return
        }

        do {
            try beginAudioSession(recognizer: recognizer)
            isRecording = true
            // Do NOT touch transcript here — real recognition output will
            // populate it. Resetting it would erase the user's prior text.
        } catch {
            errorMessage = error.localizedDescription
            cleanup()
        }
    }

    private func beginAudioSession(recognizer: SFSpeechRecognizer) throws {
        // Cancel previous task
        task?.cancel()
        task = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let result = result {
                    let spoken = result.bestTranscription.formattedString
                    let combined: String
                    if self.baseText.isEmpty {
                        combined = spoken
                    } else if spoken.isEmpty {
                        combined = self.baseText
                    } else {
                        combined = self.baseText + " " + spoken
                    }
                    let trimmed = combined.trimmingCharacters(in: .whitespaces)
                    // Never let a late/empty recognition callback erase what
                    // the user has already captured.
                    if !trimmed.isEmpty || self.transcript.isEmpty {
                        self.transcript = trimmed
                    }

                    // Voice-Activity-Detection auto-stop
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = nil
                    if result.isFinal {
                        self.stopRecording()
                    } else {
                        let autoStop = (UserDefaults.standard.object(forKey: "micAutoStop") as? Bool) ?? true
                        if autoStop {
                            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                                Task { @MainActor [weak self] in
                                    self?.stopRecording()
                                }
                            }
                        }
                    }
                }
                if error != nil {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        cleanup()
        isRecording = false
    }

    private func cleanup() {
        request = nil
        task?.cancel()
        task = nil
    }
}
