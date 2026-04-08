//
//  LlamaEngine.swift
//  Lokal
//
//  Swift wrapper around llama.cpp's modern C API (llama_model_*, llama_init_from_model,
//  llama_sampler_chain_*, llama_decode, llama_memory_clear).
//  Adapted from examples/llama.swiftui/llama.cpp.swift/LibLlama.swift.
//

import Foundation
import llama

enum LlamaError: LocalizedError {
    case modelLoadFailed(String)
    case contextInitFailed
    case decodeFailed(Int32)
    case tokenizationFailed
    case alreadyGenerating

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Failed to load model at \(path)"
        case .contextInitFailed:         return "Failed to initialize llama context"
        case .decodeFailed(let r):       return "llama_decode failed with code \(r)"
        case .tokenizationFailed:        return "Failed to tokenize input"
        case .alreadyGenerating:         return "Engine is already generating"
        }
    }
}

struct GenerationSettings: Codable, Equatable, Sendable {
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var minP: Float = 0.05
    var topK: Int32 = 40
    var maxNewTokens: Int = 512
    var contextTokens: Int32 = 4096
    var seed: UInt32 = 0xFFFF_FFFF // LLAMA_DEFAULT_SEED

    static let `default` = GenerationSettings()
}

actor LlamaEngine {

    // MARK: - State

    private let modelPtr: OpaquePointer
    private let contextPtr: OpaquePointer
    private let vocabPtr: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var nPast: Int32 = 0
    private(set) var settings: GenerationSettings
    private(set) var isGenerating: Bool = false
    /// Strings that should terminate generation if they appear at the end of the buffer.
    private var stopStrings: [String] = []
    private var cancelRequested: Bool = false

    // MARK: - Lifecycle

    private init(model: OpaquePointer, context: OpaquePointer, settings: GenerationSettings) {
        self.modelPtr = model
        self.contextPtr = context
        self.vocabPtr = llama_model_get_vocab(model)
        self.batch = llama_batch_init(512, 0, 1)
        self.settings = settings
        self.sampling = LlamaEngine.makeSampler(settings: settings)
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_free(contextPtr)
        llama_model_free(modelPtr)
    }

    /// One-time initialization of the llama.cpp backend. Both `LlamaEngine`
    /// (chat) and `LlamaEmbeddingEngine` (embeddings) call this on load.
    nonisolated static func backendInit() {
        struct Once { static let token: Void = { llama_backend_init() }() }
        _ = Once.token
    }

    /// Load a GGUF model from disk.
    static func load(path: String, settings: GenerationSettings = .default) throws -> LlamaEngine {
        backendInit()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        // -1 = offload all layers (Metal handles it).
        // (Some llama.cpp builds use INT32_MAX or 999; default is fine.)
        #endif

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(path)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(settings.contextTokens)
        ctxParams.n_batch = 512
        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        ctxParams.n_threads       = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaError.contextInitFailed
        }

        return LlamaEngine(model: model, context: context, settings: settings)
    }

    // MARK: - Sampler

    private static func makeSampler(settings: GenerationSettings) -> UnsafeMutablePointer<llama_sampler> {
        let params = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(params)!
        if settings.topK > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(settings.topK))
        }
        if settings.topP > 0 && settings.topP < 1.0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(settings.topP, 1))
        }
        if settings.minP > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(settings.minP, 1))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_temp(settings.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(settings.seed))
        return chain
    }

    func updateSettings(_ newSettings: GenerationSettings) {
        self.settings = newSettings
        let oldSampler = sampling
        sampling = LlamaEngine.makeSampler(settings: newSettings)
        llama_sampler_free(oldSampler)
    }

    // MARK: - Tokenization helpers

    private func tokenize(_ text: String, addBOS: Bool) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        // First call with -capacity returns the count we need.
        let bufferSize = max(utf8Count + (addBOS ? 1 : 0) + 1, 64)
        var tokens = [llama_token](repeating: 0, count: bufferSize)
        let n = text.withCString { cstr in
            llama_tokenize(vocabPtr, cstr, Int32(utf8Count),
                           &tokens, Int32(bufferSize),
                           addBOS, /* parse_special */ true)
        }
        if n < 0 {
            // Buffer too small — try again with the requested capacity.
            let needed = Int(-n)
            tokens = [llama_token](repeating: 0, count: needed)
            let n2 = text.withCString { cstr in
                llama_tokenize(vocabPtr, cstr, Int32(utf8Count),
                               &tokens, Int32(needed),
                               addBOS, true)
            }
            if n2 < 0 { throw LlamaError.tokenizationFailed }
            return Array(tokens.prefix(Int(n2)))
        }
        return Array(tokens.prefix(Int(n)))
    }

    private func tokenToBytes(_ token: llama_token) -> [CChar] {
        var buffer = [CChar](repeating: 0, count: 16)
        let n = llama_token_to_piece(vocabPtr, token, &buffer, Int32(buffer.count), 0, /* special */ false)
        if n < 0 {
            let needed = Int(-n)
            buffer = [CChar](repeating: 0, count: needed)
            let n2 = llama_token_to_piece(vocabPtr, token, &buffer, Int32(needed), 0, false)
            if n2 < 0 { return [] }
            return Array(buffer.prefix(Int(n2)))
        }
        return Array(buffer.prefix(Int(n)))
    }

    // MARK: - KV cache control

    func reset() {
        llama_memory_clear(llama_get_memory(contextPtr), true)
        nPast = 0
    }

    func cancel() {
        cancelRequested = true
    }

    // MARK: - Generation

    /// Stream tokens for the given fully-rendered prompt.
    /// The caller is responsible for chat templating; this just runs prefill + decode loop.
    /// Resets the KV cache before prefilling so each call is self-contained.
    func generate(prompt: String, stopStrings: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    if isGenerating {
                        continuation.finish(throwing: LlamaError.alreadyGenerating)
                        return
                    }
                    isGenerating = true
                    cancelRequested = false
                    self.stopStrings = stopStrings
                    defer {
                        isGenerating = false
                        self.stopStrings = []
                    }

                    // Reset KV between turns (simple, correct, slightly slower).
                    reset()

                    let tokens = try tokenize(prompt, addBOS: false)
                    if tokens.isEmpty {
                        continuation.finish()
                        return
                    }

                    let nCtx = Int32(settings.contextTokens)
                    let maxPrompt = nCtx - Int32(min(settings.maxNewTokens, 256))
                    let truncated: [llama_token]
                    if Int32(tokens.count) > maxPrompt {
                        // Keep last maxPrompt tokens (drop oldest history).
                        truncated = Array(tokens.suffix(Int(maxPrompt)))
                    } else {
                        truncated = tokens
                    }

                    // Prefill in batches of 512 (the batch capacity we initialized with).
                    let batchSize = 512
                    var i = 0
                    while i < truncated.count {
                        if cancelRequested { break }
                        let end = min(i + batchSize, truncated.count)
                        llama_batch_clear(&batch)
                        for j in i..<end {
                            llama_batch_add(
                                &batch,
                                token: truncated[j],
                                pos: Int32(nPast) + Int32(j - i),
                                seqIDs: [0],
                                logits: false
                            )
                        }
                        // Need logits for the very last prompt token of the very last batch.
                        if end == truncated.count {
                            batch.logits[Int(batch.n_tokens) - 1] = 1
                        }
                        let r = llama_decode(contextPtr, batch)
                        if r != 0 { throw LlamaError.decodeFailed(r) }
                        nPast += Int32(end - i)
                        i = end
                    }

                    // Decode loop.
                    var pendingBytes: [CChar] = []
                    var emittedString = ""
                    var tokensEmitted = 0
                    while tokensEmitted < settings.maxNewTokens {
                        if cancelRequested { break }
                        let newToken = llama_sampler_sample(sampling, contextPtr, batch.n_tokens - 1)
                        if llama_vocab_is_eog(vocabPtr, newToken) { break }

                        let bytes = tokenToBytes(newToken)
                        pendingBytes.append(contentsOf: bytes)

                        // Try to flush as a UTF-8 string.
                        var flushed = ""
                        if let s = String(validatingUTF8: pendingBytes + [0]) {
                            flushed = s
                            pendingBytes.removeAll(keepingCapacity: true)
                        }

                        if !flushed.isEmpty {
                            emittedString += flushed
                            // Stop string detection (substring at the tail of the emitted text).
                            if let cutoff = stopStringIndex(in: emittedString, stops: stopStrings) {
                                let trimmed = String(emittedString[..<cutoff])
                                let delta = String(trimmed.suffix(trimmed.count - (emittedString.count - flushed.count)))
                                if !delta.isEmpty { continuation.yield(delta) }
                                break
                            } else {
                                continuation.yield(flushed)
                            }
                        }

                        // Decode the new token.
                        llama_batch_clear(&batch)
                        llama_batch_add(&batch, token: newToken, pos: nPast, seqIDs: [0], logits: true)
                        let r = llama_decode(contextPtr, batch)
                        if r != 0 { throw LlamaError.decodeFailed(r) }
                        nPast += 1
                        tokensEmitted += 1
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func stopStringIndex(in text: String, stops: [String]) -> String.Index? {
        for stop in stops where !stop.isEmpty {
            if let r = text.range(of: stop) {
                return r.lowerBound
            }
        }
        return nil
    }
}

// MARK: - llama_batch helpers

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(_ batch: inout llama_batch,
                             token: llama_token,
                             pos: llama_pos,
                             seqIDs: [llama_seq_id],
                             logits: Bool) {
    let i = Int(batch.n_tokens)
    batch.token   [i] = token
    batch.pos     [i] = pos
    batch.n_seq_id[i] = Int32(seqIDs.count)
    for k in 0..<seqIDs.count {
        batch.seq_id[i]![k] = seqIDs[k]
    }
    batch.logits  [i] = logits ? 1 : 0
    batch.n_tokens += 1
}
