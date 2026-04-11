//
//  ModelDetailView.swift
//  Lokal
//

import SwiftUI

struct ModelDetailView: View {
    let entry: ModelEntry
    @Environment(ModelStore.self) private var modelStore
    @Environment(DownloadManager.self) private var downloadManager
    @Binding var path: NavigationPath
    @State private var showDeleteConfirm = false
    @State private var showCellularConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                specGrid
                description
                stateSection
                if isInstalled {
                    dangerZone
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .lokaloThemedBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Modell löschen?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                modelStore.remove(entry.id)
                if path.count > 0 { path.removeLast() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("\(entry.displayName) wird vom Gerät entfernt.")
        }
        .alert("Über Mobilfunk laden?",
               isPresented: $showCellularConfirm) {
            Button("Trotzdem laden") {
                downloadManager.startDownload(for: entry, force: true)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Du bist gerade im Mobilfunknetz. \(entry.displayName) ist \(String(format: "%.2f GB", entry.sizeGB)) groß — das kann dein Datenvolumen verbrauchen. In den Einstellungen kannst du Downloads über Mobilfunk dauerhaft erlauben.")
        }
    }

    /// Entry-point that every "Herunterladen" tap goes through. When the
    /// user is on cellular and hasn't opted in, we surface the confirmation
    /// alert instead of silently refusing the request.
    private func requestDownload() {
        if downloadManager.cellularDownloadsBlocked {
            showCellularConfirm = true
        } else {
            downloadManager.startDownload(for: entry)
        }
    }

    private var isInstalled: Bool { modelStore.isInstalled(entry.id) }
    private var task: DownloadTask? { downloadManager.task(for: entry.id) }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.publisher.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(entry.displayName)
                .font(.largeTitle.weight(.bold))
            HStack(spacing: 8) {
                badge(entry.parametersLabel)
                badge(entry.quantization)
                if let tag = entry.ollamaTag {
                    badge(tag).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var specGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            specCard(title: "Größe", value: String(format: "%.2f GB", entry.sizeGB))
            specCard(title: "RAM (ungefähr)", value: String(format: "%.1f GB", entry.ramGB))
            specCard(title: "Parameter", value: entry.parametersLabel)
            specCard(title: "Kontext", value: "\(entry.recommendedContextTokens) Token")
        }
    }

    private func specCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Über")
                .font(.headline)
            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Lizenz: \(entry.license.displayLabel)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stateSection: some View {
        if isInstalled {
            Button {
                modelStore.setActive(entry.id)
                path = NavigationPath()
            } label: {
                Label(
                    modelStore.activeID == entry.id ? "Aktiv" : "Aktivieren & Chatten",
                    systemImage: modelStore.activeID == entry.id ? "checkmark.circle.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(modelStore.activeID == entry.id)
        } else if let task, task.state == .downloading || task.state == .paused {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: task.progress)
                    .tint(.accentColor)
                HStack {
                    Text("\(formatBytes(task.bytesDownloaded)) / \(formatBytes(task.bytesTotal))")
                    if task.bytesPerSecond > 0 {
                        Text("·")
                        Text("\(formatBytes(Int64(task.bytesPerSecond)))/s")
                    }
                    Spacer()
                    Text(String(format: "%.0f%%", task.progress * 100))
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    downloadManager.cancel(task.id)
                } label: {
                    Label("Abbrechen", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        } else if let task, task.state == .verifying {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Wird überprüft…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if let task, case .failed(let msg) = task.state {
            VStack(alignment: .leading, spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    requestDownload()
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button {
                requestDownload()
            } label: {
                Label("Herunterladen · \(String(format: "%.2f GB", entry.sizeGB))",
                      systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var dangerZone: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Modell löschen", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.18))
            )
            .foregroundStyle(Color.accentColor)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
