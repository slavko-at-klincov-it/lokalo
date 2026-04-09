//
//  DownloadConfirmSheet.swift
//  Lokal
//
//  Bestätigungs-Sheet vor dem Download eines neuen Modells.
//  Zeigt: Modellgröße, freier Speicher, optionale Eviction der bereits
//  installierten Modelle, damit Platz frei wird.
//

import SwiftUI

struct DownloadConfirmSheet: View {
    let entry: ModelEntry
    @Environment(ModelStore.self) private var modelStore
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEvictionIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.displayName)
                            .font(.title2.weight(.semibold))
                        Text(entry.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            metaTag(entry.effectiveParametersLabel)
                            metaTag(entry.quantization)
                            metaTag(String(format: "%.1f GB", entry.sizeGB))
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Speicher") {
                    storageRow(
                        title: "Aktuell frei",
                        value: formatBytes(modelStore.freeDiskBytes),
                        tint: .secondary
                    )
                    storageRow(
                        title: "Modellgröße",
                        value: formatBytes(entry.sizeBytes),
                        tint: .primary
                    )
                    if freedBytesFromSelection > 0 {
                        storageRow(
                            title: "Wird freigegeben",
                            value: "+ " + formatBytes(freedBytesFromSelection),
                            tint: .green
                        )
                    }
                    storageRow(
                        title: "Verbleibend nach Download",
                        value: formatBytes(remainingAfterDownload),
                        tint: remainingAfterDownload < 0 ? .red : .secondary
                    )
                }

                if !candidatePool.isEmpty {
                    Section {
                        ForEach(candidatePool) { candidate in
                            evictionRow(candidate)
                        }
                    } header: {
                        Text("Andere Modelle löschen?")
                    } footer: {
                        if !modelStore.canFit(entry) && freedBytesFromSelection == 0 {
                            Text("Der Speicherplatz reicht nicht. Wähle Modelle zum Löschen aus, um Platz zu schaffen.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Aktive Modelle bleiben unangetastet. Du kannst sie später jederzeit erneut herunterladen.")
                        }
                    }
                }
            }
            .lokaloThemedBackground()
            .navigationTitle("Modell laden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(confirmButtonTitle) { confirm() }
                        .bold()
                        .disabled(!canConfirm)
                }
            }
            .task {
                modelStore.refreshDiskUsage()
                // Pre-tick the smallest set that makes the new model fit.
                if !modelStore.canFit(entry) {
                    selectedEvictionIDs = Set(modelStore.evictionCandidates(for: entry).map(\.id))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var candidatePool: [ModelEntry] {
        modelStore.installedModels
            .filter { $0.id != entry.id && $0.id != modelStore.activeID }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private var freedBytesFromSelection: Int64 {
        candidatePool
            .filter { selectedEvictionIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    private var remainingAfterDownload: Int64 {
        modelStore.freeDiskBytes + freedBytesFromSelection - entry.sizeBytes
    }

    private var canConfirm: Bool {
        remainingAfterDownload >= ModelStore.safetyHeadroomBytes
    }

    private var confirmButtonTitle: String {
        if freedBytesFromSelection > 0 { return "Löschen & Laden" }
        return "Herunterladen"
    }

    private func confirm() {
        // Delete every selected eviction candidate first.
        for id in selectedEvictionIDs {
            modelStore.remove(id)
        }
        downloadManager.startDownload(for: entry)
        dismiss()
    }

    @ViewBuilder
    private func storageRow(title: String, value: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private func evictionRow(_ candidate: ModelEntry) -> some View {
        Button {
            if selectedEvictionIDs.contains(candidate.id) {
                selectedEvictionIDs.remove(candidate.id)
            } else {
                selectedEvictionIDs.insert(candidate.id)
            }
        } label: {
            HStack {
                Image(systemName: selectedEvictionIDs.contains(candidate.id)
                      ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedEvictionIDs.contains(candidate.id)
                                     ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(candidate.parametersLabel) · \(formatBytes(candidate.sizeBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func metaTag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let abs = bytes < 0 ? -bytes : bytes
        let formatted = ByteCountFormatter.string(fromByteCount: abs, countStyle: .file)
        return bytes < 0 ? "-" + formatted : formatted
    }
}
