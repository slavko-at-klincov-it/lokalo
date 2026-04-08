//
//  MessageBubble.swift
//  Lokal
//

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    @State private var caretOpacity: Double = 1.0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            switch message.role {
            case .user:
                Spacer(minLength: 40)
                userBubble
            case .assistant:
                assistantBubble
                Spacer(minLength: 40)
            case .system:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor)
            )
            .textSelection(.enabled)
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.content.isEmpty && isStreaming {
                ProgressView()
                    .controlSize(.small)
            } else {
                Group {
                    if isStreaming {
                        Text(message.content) +
                        Text(" ▍").foregroundColor(.accentColor.opacity(caretOpacity))
                    } else {
                        Text(message.content)
                    }
                }
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .onAppear {
                    if isStreaming {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            caretOpacity = 0
                        }
                    }
                }
            }
        }
    }
}
