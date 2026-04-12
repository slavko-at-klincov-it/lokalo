//
//  ChatTemplate.swift
//  Lokal
//
//  Chat templates baked from the official model cards.
//

import Foundation

struct ChatTemplate {
    enum Family: String, Codable, Sendable, CaseIterable {
        case llama3
        case chatml
        case qwen3
        case phi3
        case phi4
        case gemma
        case gemma4
        case zephyr
    }

    /// Render an entire conversation using the given template.
    static func render(family: Family, system: String?, messages: [ChatMessage]) -> String {
        switch family {
        case .llama3:  return renderLlama3(system: system, messages: messages)
        case .chatml:  return renderChatML(system: system, messages: messages)
        case .qwen3:   return renderQwen3(system: system, messages: messages)
        case .phi3:    return renderPhi3(system: system, messages: messages)
        case .phi4:    return renderPhi4(system: system, messages: messages)
        case .gemma:   return renderGemma(system: system, messages: messages)
        case .gemma4:  return renderGemma4(system: system, messages: messages)
        case .zephyr:  return renderZephyr(system: system, messages: messages)
        }
    }

    /// Stop strings (additional to model EOG) that should terminate generation.
    static func stopStrings(family: Family) -> [String] {
        switch family {
        case .llama3:  return ["<|eot_id|>", "<|end_of_text|>"]
        case .chatml:  return ["<|im_end|>", "<|endoftext|>"]
        case .qwen3:   return ["<|im_end|>", "<|endoftext|>"]
        case .phi3:    return ["<|end|>", "<|endoftext|>"]
        case .phi4:    return ["<|end|>", "<|endoftext|>"]
        case .gemma:   return ["<end_of_turn>", "<eos>"]
        case .gemma4:  return ["<turn|>", "<eos>"]
        case .zephyr:  return ["</s>"]
        }
    }

    // MARK: - Renderers

    private static func renderLlama3(system: String?, messages: [ChatMessage]) -> String {
        var s = "<|begin_of_text|>"
        if let system, !system.isEmpty {
            s += "<|start_header_id|>system<|end_header_id|>\n\n\(system)<|eot_id|>"
        }
        for m in messages {
            switch m.role {
            case .user:
                s += "<|start_header_id|>user<|end_header_id|>\n\n\(m.content)<|eot_id|>"
            case .assistant:
                s += "<|start_header_id|>assistant<|end_header_id|>\n\n\(m.content)<|eot_id|>"
            case .system:
                continue
            }
        }
        s += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return s
    }

    private static func renderChatML(system: String?, messages: [ChatMessage]) -> String {
        var s = ""
        if let system, !system.isEmpty {
            s += "<|im_start|>system\n\(system)<|im_end|>\n"
        }
        for m in messages {
            switch m.role {
            case .user:
                s += "<|im_start|>user\n\(m.content)<|im_end|>\n"
            case .assistant:
                s += "<|im_start|>assistant\n\(m.content)<|im_end|>\n"
            case .system:
                continue
            }
        }
        s += "<|im_start|>assistant\n"
        return s
    }

    /// Qwen 3 / 3.5 family. Same im_start/im_end framing as ChatML, but the
    /// model is trained to always emit a `<think>...</think>` reasoning block
    /// before its actual reply. We pre-fill an *empty* thinking block right
    /// after the assistant prefix to put the model in non-thinking mode —
    /// this matches what `tokenizer_config.json` does when `enable_thinking`
    /// is false (default for chat) and avoids leaking `<think>` tags into
    /// the user-visible response.
    private static func renderQwen3(system: String?, messages: [ChatMessage]) -> String {
        var s = ""
        if let system, !system.isEmpty {
            s += "<|im_start|>system\n\(system)<|im_end|>\n"
        }
        for m in messages {
            switch m.role {
            case .user:
                s += "<|im_start|>user\n\(m.content)<|im_end|>\n"
            case .assistant:
                s += "<|im_start|>assistant\n\(m.content)<|im_end|>\n"
            case .system:
                continue
            }
        }
        s += "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return s
    }

    private static func renderPhi3(system: String?, messages: [ChatMessage]) -> String {
        var s = ""
        if let system, !system.isEmpty {
            s += "<|system|>\n\(system)<|end|>\n"
        }
        for m in messages {
            switch m.role {
            case .user:
                s += "<|user|>\n\(m.content)<|end|>\n"
            case .assistant:
                s += "<|assistant|>\n\(m.content)<|end|>\n"
            case .system:
                continue
            }
        }
        s += "<|assistant|>\n"
        return s
    }

    private static func renderPhi4(system: String?, messages: [ChatMessage]) -> String {
        var s = ""
        if let system, !system.isEmpty {
            s += "<|system|>\(system)<|end|>"
        }
        for m in messages {
            switch m.role {
            case .user:      s += "<|user|>\(m.content)<|end|>"
            case .assistant: s += "<|assistant|>\(m.content)<|end|>"
            case .system:    continue
            }
        }
        s += "<|assistant|>"
        return s
    }

    private static func renderGemma(system: String?, messages: [ChatMessage]) -> String {
        // Gemma has no system role; prepend system to the first user message.
        var s = "<bos>"
        var injectedSystem = system?.isEmpty == false ? system : nil
        for m in messages {
            switch m.role {
            case .user:
                let content: String
                if let sys = injectedSystem {
                    content = "\(sys)\n\n\(m.content)"
                    injectedSystem = nil
                } else {
                    content = m.content
                }
                s += "<start_of_turn>user\n\(content)<end_of_turn>\n"
            case .assistant:
                s += "<start_of_turn>model\n\(m.content)<end_of_turn>\n"
            case .system:
                continue
            }
        }
        s += "<start_of_turn>model\n"
        return s
    }

    /// Gemma 4 family. Uses `<|turn>role` / `<turn|>` framing (different
    /// from Gemma 2/3's `<start_of_turn>` / `<end_of_turn>`). Gemma 4 has
    /// native system-role support. We omit the `<|think|>` token to keep
    /// the model in non-thinking mode for on-device chat.
    private static func renderGemma4(system: String?, messages: [ChatMessage]) -> String {
        var s = "<bos>"
        if let system, !system.isEmpty {
            s += "<|turn>system\n\(system)<turn|>\n"
        }
        for m in messages {
            switch m.role {
            case .user:
                s += "<|turn>user\n\(m.content)<turn|>\n"
            case .assistant:
                s += "<|turn>model\n\(m.content)<turn|>\n"
            case .system:
                continue
            }
        }
        s += "<|turn>model\n"
        return s
    }

    private static func renderZephyr(system: String?, messages: [ChatMessage]) -> String {
        var s = ""
        if let system, !system.isEmpty {
            s += "<|system|>\n\(system)</s>\n"
        }
        for m in messages {
            switch m.role {
            case .user:
                s += "<|user|>\n\(m.content)</s>\n"
            case .assistant:
                s += "<|assistant|>\n\(m.content)</s>\n"
            case .system:
                continue
            }
        }
        s += "<|assistant|>\n"
        return s
    }
}
