//
//  AboutView.swift
//  Lokalo
//

import SwiftUI

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 24)
                    Text("Lokalo")
                        .font(.largeTitle.bold())
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Lokalo lädt Sprachmodelle direkt auf dein iPhone und führt sie offline aus. Keine Cloud, keine Konten, keine Telemetrie. Alles was du eintippst und was das Modell antwortet, bleibt auf deinem Gerät.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://klincov.it/lokal")!) {
                        Label("Webseite", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://klincov.it/lokal/support")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://klincov.it/lokal/privacy")!) {
                        Label("Datenschutz", systemImage: "lock.shield")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                Text("Made in Wien · Klincov IT")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)

                Spacer(minLength: 24)
            }
        }
        .navigationTitle("Über")
        .navigationBarTitleDisplayMode(.inline)
    }
}
