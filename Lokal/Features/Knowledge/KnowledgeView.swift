//
//  KnowledgeView.swift
//  Lokal
//
//  Top-level view for managing knowledge bases (RAG sources). Lets the user
//  add local folders, GitHub repos, Google Drive folders, OneDrive folders,
//  and watches indexing progress.
//

import SwiftUI

struct KnowledgeView: View {
    @Environment(KnowledgeBaseStore.self) private var kbStore
    @Environment(IndexingService.self) private var indexer
    @Environment(EmbeddingModelStore.self) private var embedStore
    @Environment(EmbeddingDownloader.self) private var embedDownloader
    @Environment(ConnectionStore.self) private var connections
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSource = false
    @State private var showEmbeddingSetup = false

    var body: some View {
        @Bindable var kb = kbStore
        NavigationStack {
            List {
                if !embedStore.hasInstalled {
                    Section {
                        embeddingMissingBanner
                    }
                }

                Section {
                    Toggle("RAG für Chat aktivieren", isOn: $kb.ragEnabled)
                        .onChange(of: kb.ragEnabled) { _, _ in
                            try? kbStore.persist()
                        }
                } footer: {
                    Text("Wenn aktiviert, sucht Lokalo bei jeder Frage in deinen Wissensbasen und übergibt die besten Treffer dem Chat-Modell.")
                }

                if let active = kbStore.activeBase {
                    Section("\(active.name)") {
                        if active.sources.isEmpty {
                            Text("Noch keine Quellen. Tippe + um eine hinzuzufügen.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(active.sources) { source in
                                sourceRow(source: source)
                            }
                            .onDelete { indexSet in
                                for i in indexSet {
                                    kbStore.remove(source: active.sources[i])
                                }
                            }
                        }
                    }
                }

                if let progress = indexer.current {
                    Section("Indizierung läuft") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.sourceName).font(.subheadline.weight(.medium))
                            ProgressView(value: Double(progress.processedFiles),
                                         total: Double(max(progress.totalFiles, 1)))
                            HStack {
                                Text("\(progress.processedFiles) / \(progress.totalFiles) Dateien")
                                Spacer()
                                Text("\(progress.indexedChunks) Chunks")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Button("Abbrechen", role: .destructive) {
                                indexer.cancel()
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let err = indexer.lastError {
                    Section("Fehler") {
                        Text(err).font(.callout).foregroundStyle(.red)
                    }
                }

                Section {
                    NavigationLink {
                        EmbeddingModelSetupView()
                    } label: {
                        Label("Embedding-Modell verwalten", systemImage: "cpu")
                    }
                }
            }
            .navigationTitle("Wissen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !embedStore.hasInstalled {
                            showEmbeddingSetup = true
                        } else {
                            ensureBaseExists()
                            showAddSource = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSource) {
                AddSourceSheet()
            }
            .sheet(isPresented: $showEmbeddingSetup) {
                NavigationStack { EmbeddingModelSetupView() }
            }
        }
    }

    private var embeddingMissingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Embedding-Modell fehlt", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("RAG braucht ein lokales Embedding-Modell. Lade es einmal herunter (~85 MB) — danach läuft alles offline.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                showEmbeddingSetup = true
            } label: {
                Label("Modell laden", systemImage: "arrow.down.circle")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }

    private func sourceRow(source: KnowledgeSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: source.kind.iconName)
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName).font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(source.kind.label).font(.caption).foregroundStyle(.secondary)
                    if source.indexedChunks > 0 {
                        Text("• \(source.indexedChunks) Chunks").font(.caption).foregroundStyle(.secondary)
                    }
                    if source.status == .indexing {
                        Text("• indiziert…").font(.caption).foregroundStyle(.orange)
                    } else if source.status == .ready {
                        Text("• bereit").font(.caption).foregroundStyle(.green)
                    } else if source.status == .error {
                        Text("• Fehler").font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Spacer()
            Button {
                if let baseID = kbStore.activeBase?.id {
                    indexer.indexSource(source, in: baseID)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(indexer.current != nil)
        }
        .contentShape(Rectangle())
    }

    private func ensureBaseExists() {
        guard let entry = embedStore.activeEntry else { return }
        _ = kbStore.createBaseIfNeeded(
            name: "Meine Wissensbasis",
            embeddingModelID: entry.id,
            dimensions: entry.dimensions
        )
    }
}
