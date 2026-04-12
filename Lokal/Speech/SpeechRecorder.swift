//
//  SpeechRecorder.swift
//  Lokal
//
//  High-level speech-to-text recorder for SwiftUI.
//
//  Combines SpeechAnalyzerBridge (audio + transcription) with
//  SpeechVocabularyService (auto-correction). Designed to feed transcription
//  text directly into the ChatView's input binding.
//
//  Lifecycle:
//    .idle → start() → .starting → .listening → stop() → .stopping → .idle
//

import Foundation
import AVFoundation
import SwiftUI

@available(iOS 26, *)
@MainActor
@Observable
final class SpeechRecorder {

    enum State: Equatable {
        case idle
        case starting
        case listening
        case stopping
    }

    // MARK: - Observable State

    private(set) var state: State = .idle
    private(set) var error: String?

    /// Original (uncorrected) transcript — kept for learning at send time.
    private(set) var originalTranscript: String = ""

    // MARK: - Private

    /// Accumulated final transcript segments (vocabulary-corrected).
    private var finalTranscript: String = ""
    private let bridge = SpeechAnalyzerBridge()
    private let vocabulary: SpeechVocabularyService
    /// Binding to the ChatView's input text field.
    private var inputBinding: Binding<String>?
    /// Text that was in the input field before dictation started.
    private var preDictationInput: String = ""
    /// Last time we updated the input binding — used for 100ms throttling.
    private var lastInterimUpdate: Date = .distantPast

    init(vocabulary: SpeechVocabularyService) {
        self.vocabulary = vocabulary
    }

    // MARK: - Public API

    /// Start recording. Writes interim + final text into the provided binding.
    func start(into inputBinding: Binding<String>, locale: Locale = Locale(identifier: "de-DE")) async {
        guard state == .idle else { return }

        guard await requestPermissions() else {
            error = "Mikrofon- oder Spracherkennungsberechtigung verweigert."
            return
        }

        guard await SpeechAnalyzerBridge.isAvailable(locale: locale) else {
            error = "Spracherkennung für diese Sprache nicht verfügbar."
            return
        }

        state = .starting
        self.inputBinding = inputBinding
        preDictationInput = inputBinding.wrappedValue
        finalTranscript = ""
        originalTranscript = ""
        error = nil

        do {
            try await bridge.start(
                locale: locale,
                onResult: { [weak self] result in
                    Task { @MainActor in
                        self?.handleResult(result)
                    }
                },
                onError: { [weak self] err in
                    Task { @MainActor in
                        self?.error = err.lokaloMessage
                        self?.state = .idle
                    }
                }
            )
            state = .listening
        } catch {
            self.error = error.lokaloMessage
            state = .idle
        }
    }

    /// Stop recording gracefully — waits for the final transcription.
    func stop() async {
        guard state == .listening || state == .starting else { return }
        state = .stopping
        await bridge.stop()

        // Ensure final text is in the input field
        updateInputBinding(with: "")
        state = .idle
    }

    /// Cancel recording immediately and restore input to pre-dictation state.
    func cancel() {
        bridge.cancel()
        inputBinding?.wrappedValue = preDictationInput
        state = .idle
        finalTranscript = ""
        originalTranscript = ""
    }

    /// Returns true if there is a transcript that can be learned from
    /// (original differs from what the user will send).
    var hasTranscriptForLearning: Bool {
        !originalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Clears the original transcript tracking (call after learning).
    func clearOriginalTranscript() {
        originalTranscript = ""
    }

    // MARK: - Private

    private func handleResult(_ result: SpeechAnalyzerBridge.TranscriptionResult) {
        if result.isFinal {
            // Accumulate raw text for learning
            originalTranscript = originalTranscript.isEmpty
                ? result.text
                : "\(originalTranscript) \(result.text)"

            // Apply vocabulary corrections
            let corrected = vocabulary.applyCorrections(result.text)
            finalTranscript = finalTranscript.isEmpty
                ? corrected
                : "\(finalTranscript) \(corrected)"

            updateInputBinding(with: "")
        } else {
            // Throttle interim updates: max 1 per 100ms
            let now = Date()
            if now.timeIntervalSince(lastInterimUpdate) >= 0.1 {
                lastInterimUpdate = now
                updateInputBinding(with: result.text)
            }
        }
    }

    /// Updates the ChatView input binding: preDictation + final + interim.
    private func updateInputBinding(with interimText: String) {
        var composed = preDictationInput
        if !composed.isEmpty && !finalTranscript.isEmpty {
            composed += " "
        }
        composed += finalTranscript
        if !interimText.isEmpty {
            if !composed.isEmpty { composed += " " }
            composed += interimText
        }
        inputBinding?.wrappedValue = composed
    }

    /// SpeechAnalyzer (iOS 26) runs fully on-device and only needs microphone
    /// permission — no SFSpeechRecognizer.requestAuthorization() required.
    /// (That API is for server-based recognition which sends audio to Apple.)
    private func requestPermissions() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
