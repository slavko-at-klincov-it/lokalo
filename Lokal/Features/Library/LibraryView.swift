//
//  LibraryView.swift
//  Lokal
//

import SwiftUI

/// How rows in the catalog list are grouped into sections.
enum ModelGrouping: String, CaseIterable, Identifiable {
    case publisher
    case sizeBucket
    case none

    var id: String { rawValue }
    var label: String {
        switch self {
        case .publisher:  return "Anbieter"
        case .sizeBucket: return "Größe"
        case .none:       return "Keine"
        }
    }
}

/// How rows in the catalog list are sorted within their section.
enum ModelSort: String, CaseIterable, Identifiable {
    case nameAsc
    case sizeAsc
    case sizeDesc
    case paramsAsc
    case paramsDesc

    var id: String { rawValue }
    var label: String {
        switch self {
        case .nameAsc:    return "Name (A–Z)"
        case .sizeAsc:    return "Größe ↑"
        case .sizeDesc:   return "Größe ↓"
        case .paramsAsc:  return "Parameter ↑"
        case .paramsDesc: return "Parameter ↓"
        }
    }
}

struct LibraryView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(DownloadManager.self) private var downloadManager
    @Binding var path: NavigationPath
    @State private var query: String = ""
    @AppStorage("Lokal.libraryGrouping") private var groupingRaw = ModelGrouping.publisher.rawValue
    @AppStorage("Lokal.librarySort") private var sortRaw = ModelSort.paramsAsc.rawValue
    /// User's first-launch model choice. The matching catalog row gets a
    /// "Empfohlen"-tag and is sorted to the top of its section. Once any
    /// model is installed the highlight disappears (see `showsPreferredHighlight`).
    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID
    @State private var pendingDownload: ModelEntry?

    /// Whether to highlight the preferred-first-model row. Only shown while
    /// no model is installed yet — once the user has anything on disk the
    /// recommendation has served its purpose and shouldn't keep nagging.
    private var showsPreferredHighlight: Bool {
        modelStore.installedModels.isEmpty
    }
    @State private var pendingDelete: ModelEntry?

    private var grouping: ModelGrouping {
        ModelGrouping(rawValue: groupingRaw) ?? .publisher
    }
    private var sort: ModelSort {
        ModelSort(rawValue: sortRaw) ?? .paramsAsc
    }

    var body: some View {
        List {
            diskSummarySection

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

            ForEach(suggestionSections, id: \.title) { section in
                Section {
                    ForEach(section.items) { entry in
                        suggestedRow(entry)
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bibliothek")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Modelle durchsuchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .overlay {
            if modelStore.installedModels.isEmpty
                && suggestionSections.allSatisfy({ $0.items.isEmpty })
                && activeDownloads.isEmpty {
                emptyState
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

    // MARK: - Sections

    private var diskSummarySection: some View {
        Section {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speicher")
                        .font(.subheadline.weight(.semibold))
                    Text("\(formatBytes(modelStore.freeDiskBytes)) frei · \(formatBytes(modelStore.totalInstalledBytes)) belegt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct CatalogSection {
        let title: String
        let items: [ModelEntry]
    }

    private var filteredCatalog: [ModelEntry] {
        let pool = modelStore.allCatalogModels.filter { !modelStore.installedIDs.contains($0.id) }
        if query.isEmpty { return pool }
        let q = query.lowercased()
        return pool.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.ollamaTag ?? "").lowercased().contains(q)
            || $0.publisher.lowercased().contains(q)
            || $0.summary.lowercased().contains(q)
        }
    }

    private var suggestionSections: [CatalogSection] {
        let sorted = filteredCatalog.sorted(by: sortComparator)
        switch grouping {
        case .none:
            let title = modelStore.installedModels.isEmpty ? "Vorschläge" : "Weitere Modelle"
            return [CatalogSection(title: title, items: sorted)]

        case .publisher:
            var byPublisher: [String: [ModelEntry]] = [:]
            for entry in sorted {
                byPublisher[entry.publisher, default: []].append(entry)
            }
            return byPublisher
                .map { CatalogSection(title: $0.key, items: $0.value) }
                .sorted { $0.title < $1.title }
                .map { promotePreferredToTop($0) }

        case .sizeBucket:
            var buckets: [(String, [ModelEntry])] = [
                ("Bis 1 GB", []),
                ("1–2 GB", []),
                ("2–3 GB", []),
                ("Über 3 GB", [])
            ]
            for entry in sorted {
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
                .map { promotePreferredToTop($0) }
        }
    }

    /// If the preferred first model is in the section AND the highlight is
    /// active, lift it to the front of the items list. Reordering only —
    /// the row's visual badge is added in `suggestedRow`.
    private func promotePreferredToTop(_ section: CatalogSection) -> CatalogSection {
        guard showsPreferredHighlight,
              let idx = section.items.firstIndex(where: { $0.id == preferredFirstModelID }),
              idx > 0
        else {
            return section
        }
        var items = section.items
        let preferred = items.remove(at: idx)
        items.insert(preferred, at: 0)
        return CatalogSection(title: section.title, items: items)
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

    private var activeDownloads: [DownloadTask] {
        downloadManager.tasks.values
            .filter { task in
                if case .completed = task.state { return false }
                return true
            }
            .sorted { $0.entry.displayName < $1.entry.displayName }
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
                    localBadge
                    if modelStore.activeID == entry.id {
                        Image(systemName: "checkmark.circle.fill")
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
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = entry
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
        let isPreferred = showsPreferredHighlight && entry.id == preferredFirstModelID
        return Button {
            path.append(Route.modelDetail(entry.id))
        } label: {
            HStack(spacing: 12) {
                publisherIcon(entry.publisher)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if isPreferred {
                            preferredBadge
                        }
                    }
                    Text(entry.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(entry.effectiveParametersLabel)
                        Text("·")
                        Text(String(format: "%.1f GB", entry.sizeGB))
                        if isPreferred {
                            Text("·")
                            Text("Tippe zum Laden")
                                .foregroundStyle(Color.accentColor)
                        }
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
        .listRowBackground(
            isPreferred
                ? Color.accentColor.opacity(0.06)
                : nil
        )
    }

    private var preferredBadge: some View {
        Text("EMPFOHLEN")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.16))
            )
            .overlay(
                Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
            )
    }

    private var localBadge: some View {
        Text("Lokal")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
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
