//
//  UserProfileEditor.swift
//  Lokal
//
//  Simple text editor for the global "Über mich" user profile.
//  The text is injected into every chat's system prompt (unless
//  the per-chat toggle is off).
//

import SwiftUI

struct UserProfileEditor: View {
    @Binding var text: String
    private let maxLength = 500

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .font(.callout)
                    .onChange(of: text) { _, newValue in
                        if newValue.count > maxLength {
                            text = String(newValue.prefix(maxLength))
                        }
                    }
            } footer: {
                HStack {
                    Text("z. B. \u{201E}Ich bin iOS-Entwickler, arbeite mit Swift und SwiftUI, spreche Deutsch.\u{201C}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(text.count)/\(maxLength)")
                        .font(.caption)
                        .foregroundStyle(text.count > maxLength - 50 ? .orange : .secondary)
                        .monospacedDigit()
                }
            }
        }
        .lokaloThemedBackground()
        .navigationTitle("Über mich")
        .navigationBarTitleDisplayMode(.inline)
    }
}
