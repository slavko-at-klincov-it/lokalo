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
    case contextTooSmall(nCtx: Int32, maxNewTokens: Int)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):       return "Failed to load model at \(path)"
        case .contextInitFailed:               return "Failed to initialize llama context"
        case .decodeFailed(let r):             return "llama_decode failed with code \(r)"
        case .tokenizationFailed:              return "Failed to tokenize input"
        case .alreadyGenerating:               return "Engine is already generating"
        case .contextTooSmall(let n, let m):
            return "Context window (\(n) tokens) is too small for the requested maxNewTokens (\(m))."
        }
    }
}

struct GenerationSettings: Codable, Equatable, Hashable, Sendable {
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var minP: Float = 0.05
    var topK: Int32 = 40
    var maxNewTokens: Int = 512
    var contextTokens: Int32 = 4096
    var seed: UInt32 = 0xFFFF_FFFF // LLAMA_DEFAULT_SEED
    /// Repetition penalty as used by `llama_sampler_init_penalties`.
    /// `1.0` = no penalty (default for most models). Qwen 2.5 specifies
    /// `1.1` officially. Values < 1.0 actively encourage repetition and
    /// are almost always wrong.
    var repetitionPenalty: Float = 1.0
    /// Sliding window the repetition penalty looks back over. 64 tokens
    /// matches llama.cpp's default and is fine for chat-length inputs.
    var repetitionPenaltyLastN: Int32 = 64

    /// Explicit empty initializer so the property-default values are
    /// available to `init(from:)` below — Swift drops the synthesised
    /// memberwise init when we add a custom Decodable init.
    init() {}

    static let `default` = GenerationSettings()

    // MARK: - Codable
    //
    // Custom decoder so older `chat-sessions.json` files (which were
    // written before `repetitionPenalty` / `repetitionPenaltyLastN` existed)
    // load cleanly with the property defaults instead of throwing on the
    // missing keys. Encoder stays synthesised.

    private enum CodingKeys: String, CodingKey {
        case temperature, topP, minP, topK
        case maxNewTokens, contextTokens, seed
        case repetitionPenalty, repetitionPenaltyLastN
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Float.self, forKey: .temperature) { self.temperature = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .topP) { self.topP = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .minP) { self.minP = v }
        if let v = try c.decodeIfPresent(Int32.self, forKey: .topK) { self.topK = v }
        if let v = try c.decodeIfPresent(Int.self, forKey: .maxNewTokens) { self.maxNewTokens = v }
        if let v = try c.decodeIfPresent(Int32.self, forKey: .contextTokens) { self.contextTokens = v }
        if let v = try c.decodeIfPresent(UInt32.self, forKey: .seed) { self.seed = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .repetitionPenalty) { self.repetitionPenalty = v }
        if let v = try c.decodeIfPresent(Int32.self, forKey: .repetitionPenaltyLastN) { self.repetitionPenaltyLastN = v }
    }
}

actor LlamaEngine {

    // MARK: - State

    private var modelPtr: OpaquePointer?
    private var contextPtr: OpaquePointer?
    private let vocabPtr: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch
    private var nPast: Int32 = 0
    private(set) var settings: GenerationSettings
    private(set) var isGenerating: Bool = false
    /// Strings that should terminate generation if they appear at the end of the buffer.
    private var stopStrings: [String] = []
    private var cancelRequested: Bool = false
    private var didShutdown: Bool = false

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
        // Belt-and-suspenders cleanup. The owning store should call shutdown()
        // explicitly so the unload UI can wait on it; this is the safety net.
        if !didShutdown {
            if let s = sampling { llama_sampler_free(s) }
            llama_batch_free(batch)
            if let c = contextPtr { llama_free(c) }
            if let m = modelPtr { llama_model_free(m) }
        }
    }

    /// Tear down all llama.cpp resources synchronously inside the actor's queue.
    /// After this returns, the engine is unusable; further `generate` calls
    /// throw `.modelLoadFailed`. Idempotent.
    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        if let s = sampling {
            llama_sampler_free(s)
            sampling = nil
        }
        llama_batch_free(batch)
        batch = llama_batch()
        if let c = contextPtr {
            llama_free(c)
            contextPtr = nil
        }
        if let m = modelPtr {
            llama_model_free(m)
            modelPtr = nil
        }
    }

    /// One-time initialization of the llama.cpp backend. Both `LlamaEngine`
    /// (chat) and `LlamaEmbeddingEngine` (embeddings) call this on load.
    nonisolated static func backendInit() {
        struct Once { static let token: Void = { llama_backend_init() }() }
        _ = Once.token
    }

    /// Load a GGUF model from disk.
    ///
    /// `progress` is invoked from the loader thread with values in `0...1`.
    /// The closure must be `@Sendable` because it can be called from any thread.
    /// Loading is synchronous; call this from a background `Task.detached`.
    static func load(path: String,
                     settings: GenerationSettings = .default,
                     progress: (@Sendable (Double) -> Void)? = nil,
                     shouldCancel: (@Sendable () -> Bool)? = nil) throws -> LlamaEngine {
        backendInit()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        // -1 = offload all layers (Metal handles it).
        // (Some llama.cpp builds use INT32_MAX or 999; default is fine.)
        #endif

        // Wire up llama.cpp's progress callback. We pass an Unmanaged box that
        // owns the closure; the C callback retrieves it from user_data and
        // forwards the float. The box is released right after the load returns.
        var progressBox: Unmanaged<ProgressBox>?
        if let progress {
            let box = ProgressBox(
                callback: progress,
                cancelChecker: shouldCancel ?? { false }
            )
            let unmanaged = Unmanaged.passRetained(box)
            progressBox = unmanaged
            modelParams.progress_callback = { value, userData in
                guard let userData else { return true }
                let box = Unmanaged<ProgressBox>.fromOpaque(userData).takeUnretainedValue()
                box.callback(Double(value))
                // Returning `false` tells llama.cpp to abort the load.
                return !box.cancelChecker()
            }
            modelParams.progress_callback_user_data = unmanaged.toOpaque()
        }

        defer {
            if let box = progressBox { box.release() }
        }

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(path)
        }

        // Notify "100% loaded weights, now initializing context" — the context
        // init below is fast but visible to the user as a brief stall.
        progress?(1.0)

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

        // Repetition penalty acts on raw logits and must come first in the
        // chain. Default value is 1.0 (no penalty); we only add the sampler
        // when the model has a non-trivial value (e.g. Qwen 2.5 = 1.1) so
        // the no-op case is allocation-free.
        if settings.repetitionPenalty != 1.0 {
            llama_sampler_chain_add(
                chain,
                llama_sampler_init_penalties(
                    settings.repetitionPenaltyLastN,
                    settings.repetitionPenalty,
                    0.0,  // frequency_penalty — not exposed in GenerationSettings yet
                    0.0   // presence_penalty — not exposed in GenerationSettings yet
                )
            )
        }

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
        guard !didShutdown else { return }
        self.settings = newSettings
        if let oldSampler = sampling {
            llama_sampler_free(oldSampler)
        }
        sampling = LlamaEngine.makeSampler(settings: newSettings)
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
        guard let contextPtr else { return }
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
                    if didShutdown {
                        continuation.finish(throwing: LlamaError.modelLoadFailed("engine shut down"))
                        return
                    }
                    guard let contextPtr = self.contextPtr,
                          let sampling = self.sampling else {
                        continuation.finish(throwing: LlamaError.contextInitFailed)
                        return
                    }
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

                    // Reserve at least one token of headroom for generation.
                    // If the user picked a context smaller than the requested
                    // maxNewTokens, fail loudly instead of silently underflowing
                    // and crashing in `tokens.suffix(...)`.
                    let nCtx = Int32(settings.contextTokens)
                    let reservedForOutput = Int32(min(settings.maxNewTokens, 256))
                    guard nCtx > reservedForOutput else {
                        throw LlamaError.contextTooSmall(nCtx: nCtx, maxNewTokens: settings.maxNewTokens)
                    }
                    let maxPrompt = max(1, nCtx - reservedForOutput)
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

                    // Decode loop with stop-string-aware look-ahead buffering.
                    //
                    // We keep an `unpublished` tail of size at most
                    // `holdback` characters and only yield characters that
                    // are guaranteed not to become part of any stop string.
                    // When a stop string is matched, we drop the tail and
                    // yield only the safe prefix. This avoids ever yielding
                    // a half-stop-string and avoids the previous suffix-math
                    // bug that could crash on a negative count.
                    var pendingBytes: [CChar] = []
                    var unpublished = ""    // chars accumulated, not yet yielded to consumer
                    var tokensEmitted = 0
                    let holdback = max(1, (stopStrings.map { $0.count }.max() ?? 0))
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
                            unpublished += flushed

                            // Did a stop string fully appear in the buffer?
                            if let cutoff = stopStringIndex(in: unpublished, stops: stopStrings) {
                                let safePrefix = String(unpublished[..<cutoff])
                                if !safePrefix.isEmpty {
                                    continuation.yield(safePrefix)
                                }
                                break
                            }

                            // Stop string not (yet) present. Yield everything
                            // except the last `holdback` chars, which might
                            // still grow into a stop string after the next
                            // token. The held-back tail is yielded if and
                            // when generation finishes without a stop hit.
                            if unpublished.count > holdback {
                                let safeEnd = unpublished.index(unpublished.endIndex, offsetBy: -holdback)
                                let safePart = String(unpublished[..<safeEnd])
                                if !safePart.isEmpty {
                                    continuation.yield(safePart)
                                }
                                unpublished = String(unpublished[safeEnd...])
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
                    // If we exited the loop without hitting a stop string,
                    // flush whatever's still in the look-ahead buffer.
                    if !unpublished.isEmpty,
                       stopStringIndex(in: unpublished, stops: stopStrings) == nil {
                        continuation.yield(unpublished)
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

// MARK: - Progress callback box

/// Reference-typed wrapper around the load-progress closure so we can shuttle
/// it through `llama_progress_callback_user_data` (a `void *`).
/// `cancelChecker` is polled on every progress tick — returning `true` makes
/// the C callback return `false`, which tells llama.cpp to abort the load
/// and return `NULL`.
private final class ProgressBox: @unchecked Sendable {
    let callback: @Sendable (Double) -> Void
    let cancelChecker: @Sendable () -> Bool
    init(callback: @escaping @Sendable (Double) -> Void,
         cancelChecker: @escaping @Sendable () -> Bool = { false }) {
        self.callback = callback
        self.cancelChecker = cancelChecker
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
