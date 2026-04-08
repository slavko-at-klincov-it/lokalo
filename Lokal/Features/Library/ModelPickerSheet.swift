//
//  ModelPickerSheet.swift
//  Lokal
//

import SwiftUI

struct ModelPickerSheet: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @Binding var path: NavigationPath

    @AppStorage("Lokal.libraryGrouping") private var groupingRaw = ModelGrouping.publisher.rawValue
    @AppStorage("Lokal.librarySort") private var sortRaw = ModelSort.paramsAsc.rawValue
    @State private var pendingDownload: ModelEntry?
    @State private var pendingDelete: ModelEntry?

    private var grouping: ModelGrouping {
        ModelGrouping(rawValue: groupingRaw) ?? .publisher
    }
    private var sort: ModelSort {
        ModelSort(rawValue: sortRaw) ?? .paramsAsc
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(formatBytes(modelStore.freeDiskBytes)) frei")
                                .font(.subheadline.weight(.semibold))
                            Text("\(formatBytes(modelStore.totalInstalledBytes)) für Modelle belegt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                if !modelStore.installedModels.isEmpty {
                    Section("Lokal") {
                        ForEach(modelStore.installedModels) { entry in
                            installedRow(entry)
                        }
                    }
                }

                if modelStore.installedModels.isEmpty && availableSections.allSatisfy({ $0.items.isEmpty }) {
                    Section {
                        ContentUnavailableView("Keine Modelle verfügbar",
                                               systemImage: "tray")
                    }
                } else {
                    ForEach(availableSections, id: \.title) { section in
                        Section {
                            ForEach(section.items) { entry in
                                availableRow(entry)
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        path.append(Route.library)
                    } label: {
                        Label("Alle Modelle in der Bibliothek öffnen",
                              systemImage: "square.grid.2x2")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Modell wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Gruppieren", selection: $groupingRaw) {
                            ForEach(ModelGrouping.allCases) { g in
                                Text(g.label).tag(g.rawValue)
                            }
                        }
                        Picker("Sortieren", selection: $sortRaw) {
                            ForEach(ModelSort.allCases) { s in
                                Text(s.label).tag(s.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $pendingDownload) { entry in
                DownloadConfirmSheet(entry: entry)
            }
            .confirmationDialog(
                pendingDelete.map { "\($0.displayName) löschen?" } ?? "",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Endgültig löschen", role: .destructive) {
                    if let p = pendingDelete { modelStore.remove(p.id) }
                    pendingDelete = nil
                }
                Button("Abbrechen", role: .cancel) { pendingDelete = nil }
            }
            .task { modelStore.refreshDiskUsage() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private struct CatalogSection {
        let title: String
        let items: [ModelEntry]
    }

    private var availableSections: [CatalogSection] {
        let pool = modelStore.allCatalogModels
            .filter { !modelStore.installedIDs.contains($0.id) }
            .sorted(by: sortComparator)
        switch grouping {
        case .none:
            return [CatalogSection(title: "Verfügbar", items: pool)]

        case .publisher:
            var byPublisher: [String: [ModelEntry]] = [:]
            for entry in pool {
                byPublisher[entry.publisher, default: []].append(entry)
            }
            return byPublisher
                .map { CatalogSection(title: $0.key, items: $0.value) }
                .sorted { $0.title < $1.title }

        case .sizeBucket:
            var buckets: [(String, [ModelEntry])] = [
                ("Bis 1 GB", []),
                ("1–2 GB", []),
                ("2–3 GB", []),
                ("Über 3 GB", [])
            ]
            for entry in pool {
                let gb = entry.sizeGB
                if gb < 1.0 {
                    buckets[0].1.append(entry)
                } else if gb < 2.0 {
                    buckets[1].1.append(entry)
                } else if gb < 3.0 {
                    buckets[2].1.append(entry)
                } else {
                    buckets[3].1.append(entry)
                }
            }
            return buckets
                .filter { !$0.1.isEmpty }
                .map { CatalogSection(title: $0.0, items: $0.1) }
        }
    }

    private var sortComparator: (ModelEntry, ModelEntry) -> Bool {
        switch sort {
        case .nameAsc:    return { $0.displayName < $1.displayName }
        case .sizeAsc:    return { $0.sizeBytes < $1.sizeBytes }
        case .sizeDesc:   return { $0.sizeBytes > $1.sizeBytes }
        case .paramsAsc:  return { $0.activeParametersBillion < $1.activeParametersBillion }
        case .paramsDesc: return { $0.activeParametersBillion > $1.activeParametersBillion }
        }
    }

    private func sectionHeader(_ section: CatalogSection) -> some View {
        let totalGB = Double(section.items.reduce(0) { $0 + $1.sizeBytes }) / 1_073_741_824.0
        return HStack {
            Text(section.title)
            Spacer()
            Text("\(section.items.count) · \(String(format: "%.1f GB", totalGB))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rows

    private func installedRow(_ entry: ModelEntry) -> some View {
        HStack(spacing: 10) {
            Button {
                modelStore.setActive(entry.id)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: modelStore.activeID == entry.id
                          ? "circle.inset.filled" : "circle")
                        .foregroundStyle(modelStore.activeID == entry.id
                                         ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            localBadge
                        }
                        Text("\(entry.parametersLabel) · \(entry.quantization) · \(formatBytes(entry.sizeBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if modelStore.activeID == entry.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if modelStore.activeID == entry.id { return }
                pendingDelete = entry
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(modelStore.activeID == entry.id ? .gray : .red)
            }
            .buttonStyle(.plain)
            .disabled(modelStore.activeID == entry.id)
            .accessibilityLabel("Modell löschen")
        }
    }

    private func availableRow(_ entry: ModelEntry) -> some View {
        Button {
            pendingDownload = entry
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(entry.effectiveParametersLabel) · \(entry.quantization) · \(formatBytes(entry.sizeBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var localBadge: some View {
        Text("Lokal")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
