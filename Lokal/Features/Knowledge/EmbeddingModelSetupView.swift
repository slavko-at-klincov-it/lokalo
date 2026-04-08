//
//  EmbeddingModelSetupView.swift
//  Lokal
//
//  Lets the user download / install / select the GGUF embedding model
//  required for RAG.
//

import SwiftUI

struct EmbeddingModelSetupView: View {
    @Environment(EmbeddingModelStore.self) private var store
    @Environment(EmbeddingDownloader.self) private var downloader

    var body: some View {
        List {
            Section {
                Text("Lokalo nutzt ein lokales Embedding-Modell, um Texte zu vektorisieren. Es wird einmalig geladen und läuft danach komplett offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(EmbeddingModelCatalog.all, id: \.id) { entry in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName).font(.headline)
                                Text("\(entry.publisher) · \(Int(entry.dimensions)) dim · \(Int(entry.sizeMB)) MB")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            statusIcon(for: entry)
                        }
                        Text(entry.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        actionButton(for: entry)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Embedding-Modell")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func statusIcon(for entry: EmbeddingModelEntry) -> some View {
        if store.isInstalled(entry.id) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if downloader.currentEntryID == entry.id && downloader.state == .downloading {
            ProgressView().controlSize(.small)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func actionButton(for entry: EmbeddingModelEntry) -> some View {
        if store.isInstalled(entry.id) {
            HStack(spacing: 8) {
                if store.activeID == entry.id {
                    Label("Aktiv", systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.15), in: Capsule())
                } else {
                    Button {
                        store.setActive(entry.id)
                    } label: {
                        Label("Aktivieren", systemImage: "play")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) {
                    store.remove(entry.id)
                } label: {
                    Label("Löschen", systemImage: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        } else if downloader.currentEntryID == entry.id && downloader.state == .downloading {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: downloader.progress)
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                Task { await downloader.download(entry) }
            } label: {
                Label("Laden (\(Int(entry.sizeMB)) MB)", systemImage: "arrow.down.circle")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var progressLabel: String {
        let mb = Double(downloader.bytesDownloaded) / 1_048_576.0
        let total = Double(downloader.bytesTotal) / 1_048_576.0
        return String(format: "%.1f / %.1f MB", mb, total)
    }
}
