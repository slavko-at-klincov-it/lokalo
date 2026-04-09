//
//  StorageDiagnosticView.swift
//  Lokal
//
//  Settings-side inspector for `Documents/models/` — shows every file
//  the app sandboxed there with its size and match state against the
//  catalog. Built to diagnose the "25 GB → 13.5 GB, but 0 KB belegt"
//  kind of storage ghost where a model was physically downloaded but
//  `ModelStore.bootstrap()` refused to register it (wrong size,
//  orphan filename, or left-behind `.partial`).
//
//  Live-scans the directory via `ModelStore.scanDiskContents()` on
//  every `.task`. The result is classified into five buckets and
//  rendered as grouped sections: Installiert (green), Unfertig /
//  Partials (orange), Größe falsch (orange), Nicht im Katalog
//  (orange), Unbekannt (orange). A sticky "Aufräumen" button at the
//  bottom confirms and deletes everything that isn't `.installed`.
//

import SwiftUI

struct StorageDiagnosticView: View {
    @Environment(ModelStore.self) private var modelStore
    @State private var entries: [ModelStore.DiskEntry] = []
    @State private var showCleanupConfirm = false
    @State private var lastFreedBytes: Int64?

    var body: some View {
        List {
            summarySection

            ForEach(groupedSections, id: \.title) { section in
                Section {
                    ForEach(section.items) { entry in
                        diagnosticRow(entry)
                    }
                } header: {
                    HStack {
                        Text(section.title)
                        Spacer()
                        Text(
                            "\(section.items.count) · \(formatBytes(section.totalBytes))"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !orphans.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showCleanupConfirm = true
                    } label: {
                        Label(
                            "Alle Orphans entfernen (\(formatBytes(orphanBytes)))",
                            systemImage: "trash"
                        )
                    }
                } footer: {
                    Text("Löscht alle Dateien oben die NICHT als 'Installiert' markiert sind. Das betrifft keine aktiven Modelle.")
                        .font(.caption)
                }
            }

            if let freed = lastFreedBytes {
                Section {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("\(formatBytes(freed)) freigegeben.")
                    }
                    .font(.footnote)
                }
            }
        }
        .lokaloThemedBackground()
        .navigationTitle("Speicherdiagnose")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .confirmationDialog(
            "Orphans entfernen?",
            isPresented: $showCleanupConfirm,
            titleVisibility: .visible
        ) {
            Button("Endgültig löschen", role: .destructive) {
                let freed = modelStore.cleanupOrphans()
                lastFreedBytes = freed
                reload()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("\(orphans.count) Dateien · \(formatBytes(orphanBytes)) werden unwiderruflich gelöscht.")
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack {
                Text("Ordner")
                Spacer()
                Text("Documents/models/")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack {
                Text("Dateien gesamt")
                Spacer()
                Text("\(entries.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text("Belegt auf Disk")
                Spacer()
                Text(formatBytes(totalBytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text("Davon Installiert")
                Spacer()
                Text(formatBytes(installedBytes))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            if orphanBytes > 0 {
                HStack {
                    Text("Davon Orphans")
                    Spacer()
                    Text(formatBytes(orphanBytes))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Übersicht")
        } footer: {
            Text("Orphans sind Dateien die auf der Disk liegen, die `ModelStore.bootstrap` aber nicht als installiertes Modell erkennt – meistens abgebrochene Downloads (`.partial`), Size-Mismatches gegen den Katalog, oder Filenames die nicht im Katalog stehen.")
                .font(.caption)
        }
    }

    private struct GroupedSection {
        let title: String
        let items: [ModelStore.DiskEntry]
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    }

    private var groupedSections: [GroupedSection] {
        var installed: [ModelStore.DiskEntry] = []
        var partials: [ModelStore.DiskEntry] = []
        var sizeMismatch: [ModelStore.DiskEntry] = []
        var orphanFilenames: [ModelStore.DiskEntry] = []
        var unknown: [ModelStore.DiskEntry] = []
        for e in entries {
            switch e.status {
            case .installed:     installed.append(e)
            case .partial:       partials.append(e)
            case .sizeMismatch:  sizeMismatch.append(e)
            case .orphanFilename: orphanFilenames.append(e)
            case .unknown:       unknown.append(e)
            }
        }
        var result: [GroupedSection] = []
        if !installed.isEmpty      { result.append(.init(title: "Installiert",        items: installed)) }
        if !partials.isEmpty       { result.append(.init(title: "Unfertig (.partial)", items: partials)) }
        if !sizeMismatch.isEmpty   { result.append(.init(title: "Größe falsch",        items: sizeMismatch)) }
        if !orphanFilenames.isEmpty { result.append(.init(title: "Nicht im Katalog",   items: orphanFilenames)) }
        if !unknown.isEmpty        { result.append(.init(title: "Unbekannt",           items: unknown)) }
        return result
    }

    private var orphans: [ModelStore.DiskEntry] {
        entries.filter(\.isOrphan)
    }

    private var totalBytes: Int64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    private var installedBytes: Int64 {
        entries.filter { !$0.isOrphan }.reduce(0) { $0 + $1.sizeBytes }
    }

    private var orphanBytes: Int64 {
        orphans.reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: - Row

    private func diagnosticRow(_ entry: ModelStore.DiskEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.filename)
                .font(.footnote.monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                statusBadge(entry.status)
                Text(formatBytes(entry.sizeBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if case .sizeMismatch(_, let expected) = entry.status {
                    Text("Erwartet: \(formatBytes(expected))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ status: ModelStore.DiskEntry.Status) -> some View {
        let (label, color) = statusPresentation(status)
        Text(label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }

    private func statusPresentation(_ status: ModelStore.DiskEntry.Status) -> (String, Color) {
        switch status {
        case .installed:     return ("Installiert", .green)
        case .partial:       return ("Partial",     .orange)
        case .sizeMismatch:  return ("Größe",       .orange)
        case .orphanFilename: return ("Orphan",     .orange)
        case .unknown:       return ("Unbekannt",   .secondary)
        }
    }

    // MARK: - Helpers

    private func reload() {
        entries = modelStore.scanDiskContents()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
