//
//  PendingModelSwitchCard.swift
//  Lokal
//
//  Inline card shown in the centre of the chat viewport when the user
//  switches to a session whose `chatModelID` does not match the currently
//  loaded model. The user must explicitly confirm the (expensive) model
//  change before they can send messages in the new chat — matching the
//  user's requirement "in der Mitte zuerst ein Button auf — Modell laden?".
//

import SwiftUI

struct PendingModelSwitchCard: View {

    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelStore.self) private var modelStore

    let targetModelID: String

    private var targetEntry: ModelEntry? {
        ModelCatalog.entry(id: targetModelID)
    }

    private var targetIsInstalled: Bool {
        modelStore.isInstalled(targetModelID)
    }

    private var currentModelName: String {
        modelStore.activeModel?.displayName ?? "Kein Modell"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: iconName)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(titleText)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            actionButtons
                .padding(.horizontal, 24)
                .padding(.top, 4)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Content

    private var iconName: String {
        targetIsInstalled ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle"
    }

    private var titleText: String {
        targetIsInstalled ? "Anderes Modell benötigt" : "Modell nicht installiert"
    }

    private var detailText: String {
        if let entry = targetEntry, targetIsInstalled {
            return """
            Diese Unterhaltung verwendet **\(entry.displayName)**.
            Aktuell geladen: **\(currentModelName)**.
            """
        } else if let entry = targetEntry {
            return "Diese Unterhaltung verwendet **\(entry.displayName)**. Das Modell ist nicht mehr installiert."
        } else {
            return "Das ursprünglich verwendete Modell ist nicht mehr verfügbar."
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButtons: some View {
        if targetIsInstalled {
            VStack(spacing: 10) {
                Button {
                    ChatHaptics.confirmModelSwitch()
                    chatStore.confirmPendingModelSwitch()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Modell laden")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    chatStore.cancelPendingModelSwitch()
                } label: {
                    Text("Zurück")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        } else {
            VStack(spacing: 10) {
                Button {
                    // Cancel the pending and reset to previous session so
                    // the user lands somewhere they can actually chat in.
                    chatStore.cancelPendingModelSwitch()
                } label: {
                    Text("Zurück")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
