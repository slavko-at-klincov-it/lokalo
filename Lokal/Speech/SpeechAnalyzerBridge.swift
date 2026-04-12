//
//  SpeechAnalyzerBridge.swift
//  Lokal
//
//  Core logic for iOS 26+ SpeechAnalyzer transcription.
//
//  Pipeline:
//    AVAudioEngine mic tap → AudioBufferConverter → AsyncStream<AnalyzerInput>
//    → SpeechTranscriber → volatile (interim) + final results streamed via callback.
//

import Foundation
import AVFoundation
import Speech

@available(iOS 26, *)
final class SpeechAnalyzerBridge {

    struct TranscriptionResult: Sendable {
        let text: String
        let isFinal: Bool
    }

    typealias ResultCallback = (TranscriptionResult) -> Void
    typealias ErrorCallback = (Error) -> Void

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<(), Error>?
    private var converter = AudioBufferConverter()

    private var onResult: ResultCallback?
    private var onError: ErrorCallback?
    private var recognizerTaskCompleted = false

    /// Check if SpeechAnalyzer supports the given locale on this device.
    static func isAvailable(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    /// Start transcription. Results are delivered via `onResult`, errors via `onError`.
    func start(
        locale: Locale,
        onResult: @escaping ResultCallback,
        onError: @escaping ErrorCallback
    ) async throws {
        self.onResult = onResult
        self.onError = onError

        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        guard let transcriber else {
            throw LokaloError.speech("SpeechTranscriber konnte nicht erstellt werden.")
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        try await ensureModel(transcriber: transcriber, locale: locale)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw LokaloError.speech("Audio-Format für Spracherkennung nicht verfügbar.")
        }

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputContinuation

        recognizerTaskCompleted = false
        recognizerTask = Task { [weak self] in
            do {
                for try await case let result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.onResult?(TranscriptionResult(text: text, isFinal: result.isFinal))
                }
            } catch {
                self?.onError?(error)
            }
            self?.recognizerTaskCompleted = true
        }

        try setUpAudioSession()
        try startAudioEngine(analyzerFormat: analyzerFormat)
        try await analyzer?.start(inputSequence: inputSequence)
    }

    /// Stop transcription gracefully — finalizes any remaining audio.
    /// Waits up to 3 seconds for the final result to arrive.
    func stop() async {
        inputBuilder?.finish()
        inputBuilder = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            onError?(error)
        }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        for _ in 0..<30 {
            if recognizerTaskCompleted { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        recognizerTask?.cancel()
        recognizerTask = nil
        recognizerTaskCompleted = false
    }

    /// Cancel transcription immediately without finalizing.
    func cancel() {
        inputBuilder?.finish()
        inputBuilder = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognizerTask?.cancel()
        recognizerTask = nil
        recognizerTaskCompleted = false
    }

    // MARK: - Private

    private func setUpAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioEngine(analyzerFormat: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: engine.inputNode.outputFormat(forBus: 0)
        ) { [weak self] buffer, _ in
            guard let self, let inputBuilder = self.inputBuilder else { return }
            do {
                let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
                let input = AnalyzerInput(buffer: converted)
                inputBuilder.yield(input)
            } catch {
                self.onError?(error)
            }
        }

        engine.prepare()
        try engine.start()
    }

    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let isInstalled = installed.map { $0.identifier(.bcp47) }
            .contains(locale.identifier(.bcp47))

        if isInstalled { return }

        if let downloader = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await downloader.downloadAndInstall()
        }
    }
}
