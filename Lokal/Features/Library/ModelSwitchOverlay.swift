//
//  ModelSwitchOverlay.swift
//  Lokal
//
//  Blocking modal that drives the user through unloading the previous model
//  and loading the new one with a real progress percentage.
//

import SwiftUI

struct ModelSwitchOverlay: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelStore.self) private var modelStore

    var body: some View {
        VStack(spacing: 22) {
            iconView
            Text(titleText)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let detail = detailText {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if case .loading(_, let progress) = chatStore.loadState {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    Text("\(Int(progress * 100)) %")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 360)
                Button("Abbrechen") {
                    chatStore.cancelModelLoad()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)
                .padding(.top, 4)
            } else if case .unloading = chatStore.loadState {
                ProgressView()
                    .controlSize(.large)
            } else if case .error(let msg) = chatStore.loadState {
                VStack(spacing: 12) {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Schließen") {
                        chatStore.clearLoadError()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        )
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var iconView: some View {
        switch chatStore.loadState {
        case .unloading:
            Image(systemName: "tray.and.arrow.up")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        case .loading:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private var titleText: String {
        switch chatStore.loadState {
        case .unloading:
            return "Aktuelles Modell wird entladen…"
        case .loading:
            return "Neues Modell wird geladen…"
        case .error:
            return "Modell konnte nicht geladen werden"
        default:
            return ""
        }
    }

    private var detailText: String? {
        switch chatStore.loadState {
        case .unloading(let previousID):
            return ModelCatalog.entry(id: previousID)?.displayName
        case .loading(let id, _):
            return ModelCatalog.entry(id: id)?.displayName
        default:
            return nil
        }
    }
}

/// View modifier that presents `ModelSwitchOverlay` whenever the chat store
/// is mid-switch. Uses an in-window overlay (not a sheet) so it sits above
/// every other modal and blocks interaction without spawning a new scene.
struct ModelSwitchOverlayModifier: ViewModifier {
    @Environment(ChatStore.self) private var chatStore

    func body(content: Content) -> some View {
        content.overlay {
            if shouldShow {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    ModelSwitchOverlay()
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.18), value: chatStore.loadState)
                // Block taps from passing through.
                .contentShape(Rectangle())
                .onTapGesture { /* eat */ }
            }
        }
    }

    private var shouldShow: Bool {
        switch chatStore.loadState {
        case .unloading, .loading, .error: return true
        default: return false
        }
    }
}

extension View {
    func modelSwitchOverlay() -> some View {
        modifier(ModelSwitchOverlayModifier())
    }
}
