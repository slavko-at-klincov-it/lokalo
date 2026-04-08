//
//  ModelPickerSheet.swift
//  Lokal
//

import SwiftUI

struct ModelPickerSheet: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.dismiss) private var dismiss
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack {
            List {
                if modelStore.installedModels.isEmpty {
                    ContentUnavailableView("Keine Modelle geladen",
                                           systemImage: "tray")
                } else {
                    ForEach(modelStore.installedModels) { entry in
                        Button {
                            modelStore.setActive(entry.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: modelStore.activeID == entry.id
                                      ? "circle.inset.filled" : "circle")
                                    .foregroundStyle(modelStore.activeID == entry.id
                                                     ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("\(entry.parametersLabel) · \(entry.quantization)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if modelStore.activeID == entry.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        path.append(Route.library)
                    } label: {
                        Label("Alle Modelle durchsuchen", systemImage: "square.grid.2x2")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Modell wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
