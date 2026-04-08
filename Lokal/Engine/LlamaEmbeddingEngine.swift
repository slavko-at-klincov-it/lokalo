//
//  LlamaEmbeddingEngine.swift
//  Lokal
//
//  Sibling actor of `LlamaEngine` that loads a GGUF embedding model in
//  pooled-mean mode and exposes a single `embed(_:)` call. Designed to be
//  loaded on-demand and torn down once indexing finishes — RAM is precious.
//

import Foundation
import llama

actor LlamaEmbeddingEngine {

    private let modelPtr: OpaquePointer
    private let contextPtr: OpaquePointer
    private let vocabPtr: OpaquePointer
    private var batch: llama_batch
    let dimensions: Int
    let nCtx: Int

    private init(model: OpaquePointer, context: OpaquePointer, dim: Int, ctx: Int) {
        self.modelPtr = model
        self.contextPtr = context
        self.vocabPtr = llama_model_get_vocab(model)
        self.batch = llama_batch_init(Int32(ctx), 0, 1)
        self.dimensions = dim
        self.nCtx = ctx
    }

    deinit {
        llama_batch_free(batch)
        llama_free(contextPtr)
        llama_model_free(modelPtr)
    }

    static func load(path: String, contextTokens: Int = 2048) throws -> LlamaEmbeddingEngine {
        LlamaEngine.backendInit()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #endif

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(path)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextTokens)
        ctxParams.n_batch = UInt32(contextTokens)
        ctxParams.n_ubatch = UInt32(contextTokens)
        ctxParams.embeddings = true
        ctxParams.pooling_type = LLAMA_POOLING_TYPE_MEAN
        let nThreads = max(1, min(4, ProcessInfo.processInfo.processorCount - 4))
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaError.contextInitFailed
        }

        let dim = Int(llama_model_n_embd(model))
        return LlamaEmbeddingEngine(
            model: model,
            context: context,
            dim: dim,
            ctx: contextTokens
        )
    }

    /// Embed a single piece of text. Caller is responsible for prefixing the
    /// task tag (e.g. "search_document: " for nomic-embed).
    func embed(_ text: String) throws -> [Float32] {
        let tokens = try tokenize(text)
        guard !tokens.isEmpty else {
            return Array(repeating: 0, count: dimensions)
        }

        // Truncate to ctx if needed.
        let trimmedTokens: [llama_token] = {
            if tokens.count > nCtx { return Array(tokens.suffix(nCtx)) }
            return tokens
        }()

        // Reset and feed.
        llama_memory_clear(llama_get_memory(contextPtr), true)
        llama_batch_clear(&batch)
        for (i, t) in trimmedTokens.enumerated() {
            llama_batch_add(&batch, token: t, pos: Int32(i), seqIDs: [0], logits: false)
        }

        let r = llama_decode(contextPtr, batch)
        if r != 0 {
            throw LlamaError.decodeFailed(r)
        }

        guard let raw = llama_get_embeddings_seq(contextPtr, 0) else {
            throw LlamaError.decodeFailed(-1)
        }
        let buf = UnsafeBufferPointer(start: raw, count: dimensions)
        var vec = Array(buf)

        // L2-normalize so that cosine similarity == dot product.
        var sumSq: Float32 = 0
        for v in vec { sumSq += v * v }
        let norm = sqrt(sumSq) + 1e-9
        for i in 0..<vec.count { vec[i] /= norm }
        return vec
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        let bufferSize = max(utf8Count + 2, 64)
        var tokens = [llama_token](repeating: 0, count: bufferSize)
        let n = text.withCString { cstr in
            llama_tokenize(vocabPtr, cstr, Int32(utf8Count),
                           &tokens, Int32(bufferSize),
                           /* addBOS */ true, /* parse_special */ true)
        }
        if n < 0 {
            let needed = Int(-n)
            tokens = [llama_token](repeating: 0, count: needed)
            let n2 = text.withCString { cstr in
                llama_tokenize(vocabPtr, cstr, Int32(utf8Count),
                               &tokens, Int32(needed),
                               true, true)
            }
            if n2 < 0 { throw LlamaError.tokenizationFailed }
            return Array(tokens.prefix(Int(n2)))
        }
        return Array(tokens.prefix(Int(n)))
    }
}

// Local copies of the batch helpers (kept private in LlamaEngine.swift).
// Duplicated here so the embedding engine compiles standalone.
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
