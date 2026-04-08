//
//  LibraryView.swift
//  Lokal
//

import SwiftUI

struct LibraryView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(DownloadManager.self) private var downloadManager
    @Binding var path: NavigationPath
    @State private var query: String = ""

    var body: some View {
        List {
            if !modelStore.installedModels.isEmpty {
                Section("Geladen") {
                    ForEach(modelStore.installedModels) { entry in
                        installedRow(entry)
                    }
                }
            }

            let active = activeDownloads
            if !active.isEmpty {
                Section("Lädt…") {
                    ForEach(active, id: \.id) { task in
                        downloadingRow(task)
                    }
                }
            }

            Section(modelStore.installedModels.isEmpty ? "Vorschläge" : "Weitere Modelle") {
                ForEach(filteredSuggestions) { entry in
                    suggestedRow(entry)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bibliothek")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Modelle durchsuchen")
        .overlay {
            if modelStore.installedModels.isEmpty && filteredSuggestions.isEmpty && activeDownloads.isEmpty {
                emptyState
            }
        }
    }

    private var activeDownloads: [DownloadTask] {
        downloadManager.tasks.values
            .filter { task in
                if case .completed = task.state { return false }
                return true
            }
            .sorted { $0.entry.displayName < $1.entry.displayName }
    }

    private var filteredSuggestions: [ModelEntry] {
        let pool = ModelCatalog.all.filter { !modelStore.installedIDs.contains($0.id) }
        if query.isEmpty { return pool }
        let q = query.lowercased()
        return pool.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.ollamaTag ?? "").lowercased().contains(q)
            || $0.publisher.lowercased().contains(q)
            || $0.summary.lowercased().contains(q)
        }
    }

    private func installedRow(_ entry: ModelEntry) -> some View {
        Button {
            path.append(Route.modelDetail(entry.id))
        } label: {
            HStack(spacing: 12) {
                publisherIcon(entry.publisher)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(entry.parametersLabel)
                        Text("·")
                        Text(entry.quantization)
                        Text("·")
                        Text(String(format: "%.1f GB", entry.sizeGB))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if modelStore.activeID == entry.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelStore.remove(entry.id)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func downloadingRow(_ task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                publisherIcon(task.entry.publisher)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.entry.displayName)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(formatBytes(task.bytesDownloaded))
                        Text("/")
                        Text(formatBytes(task.bytesTotal))
                        if task.bytesPerSecond > 0 {
                            Text("·")
                            Text("\(formatBytes(Int64(task.bytesPerSecond)))/s")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    downloadManager.cancel(task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            ProgressView(value: task.progress)
                .tint(.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func suggestedRow(_ entry: ModelEntry) -> some View {
        Button {
            path.append(Route.modelDetail(entry.id))
        } label: {
            HStack(spacing: 12) {
                publisherIcon(entry.publisher)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(entry.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(entry.parametersLabel)
                        Text("·")
                        Text(String(format: "%.1f GB", entry.sizeGB))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Keine Modelle", systemImage: "tray")
        } description: {
            Text("Tippe auf ein Modell unten, um es herunterzuladen.")
        }
    }

    private func publisherIcon(_ publisher: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 36, height: 36)
            Text(String(publisher.prefix(1)))
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        LibraryView(path: .constant(NavigationPath()))
            .environment(ModelStore())
            .environment(DownloadManager())
    }
}
