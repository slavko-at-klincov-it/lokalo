//
//  Beat2EinstellungenView.swift
//  Lokalo
//
//  Second beat of the onboarding flow. Four iOS-style settings cards:
//  microphone permission, notifications permission, cellular-downloads
//  toggle, and a start-model picker.
//
//  The microphone and notifications toggles are wired to the real iOS
//  permission APIs — tapping a toggle triggers the native system popup
//  the first time (`.notDetermined`). iOS refuses to show the popup a
//  second time once the user has denied it, so for `.denied` we surface
//  an alert that points at iOS Settings. Turning OFF a granted
//  permission also points at Settings because code can never revoke an
//  already-granted permission. `refreshPermissionStates` runs on view
//  appear + after each request to keep the toggle visual in sync with
//  the real system state.
//
//  The start-model picker has two choices: "Später wählen" (empty
//  preferredFirstModelID, RootView drops the user in the empty Library)
//  or the featured entry from `models.json.suggested[].first`. No
//  selection is pre-filled — the user has to explicitly pick one.
//
//  After "Loslegen", the parent flow flips `hasCompletedOnboarding` and
//  the chat view becomes the root.
//

import SwiftUI
import AVFoundation
import UserNotifications

struct Beat2EinstellungenView: View {
    let onComplete: () -> Void

    @AppStorage(OnboardingPreferences.cellularDownloadsAllowedKey)
    private var cellularAllowed: Bool = false

    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID

    /// Live mirrors of the actual system permission states. Seeded on
    /// view-appear via `refreshPermissionStates`, updated after each
    /// request/popup. The toggle bindings read/write these.
    @State private var microphoneGranted: Bool = false
    @State private var notificationsGranted: Bool = false

    /// Flips `true` once the user has explicitly picked "Später wählen"
    /// or the featured model in the picker. Before the first interaction
    /// the picker shows "Bitte wählen" in placeholder style so the user
    /// knows the control needs their attention.
    @State private var didPickStartModel: Bool = false

    @State private var showMicSettingsAlert = false
    @State private var showNotificationSettingsAlert = false

    @State private var headerVisible = false
    @State private var micCardVisible = false
    @State private var notificationCardVisible = false
    @State private var cellularCardVisible = false
    @State private var modelCardVisible = false
    @State private var footerVisible = false

    /// The models shown in the picker menu. Contains exactly the first
    /// entry from `models.json.suggested[]` — typically the newest /
    /// featured model. The menu therefore always has two rows: "Später
    /// wählen" and this featured entry. If the catalog somehow has no
    /// suggested entries (misconfigured JSON), the picker collapses to
    /// just "Später wählen".
    private var startModelChoices: [ModelEntry] {
        if let featured = ModelCatalog.suggestedEntries().first {
            return [featured]
        }
        return []
    }

    private var selectedModelDisplayName: String {
        if !didPickStartModel && preferredFirstModelID.isEmpty {
            return "Bitte wählen"
        }
        if preferredFirstModelID.isEmpty {
            return "Später wählen"
        }
        return ModelCatalog.entry(id: preferredFirstModelID)?.displayName ?? "Später wählen"
    }

    var body: some View {
        ZStack {
            background
            ambientParticles

            VStack(spacing: 0) {
                header
                    .padding(.top, 56)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(spacing: 12) {
                    Beat2SettingCard(
                        icon: "mic",
                        title: "Mikrofon",
                        desc: "Für Sprachsteuerung und Diktat im Chat.",
                        isOn: microphoneBinding
                    )
                    .opacity(micCardVisible ? 1 : 0)
                    .offset(y: micCardVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.7), value: micCardVisible)

                    Beat2SettingCard(
                        icon: "bell",
                        title: "Benachrichtigungen",
                        desc: "Meldung wenn ein Download oder eine lange Antwort fertig ist.",
                        isOn: notificationsBinding
                    )
                    .opacity(notificationCardVisible ? 1 : 0)
                    .offset(y: notificationCardVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.7), value: notificationCardVisible)

                    Beat2SettingCard(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Modelle ohne WLAN laden",
                        desc: "Standardmäßig nur über WLAN — sind oft 1–4 GB.",
                        isOn: $cellularAllowed
                    )
                    .opacity(cellularCardVisible ? 1 : 0)
                    .offset(y: cellularCardVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.7), value: cellularCardVisible)

                    Beat2ModelCard(
                        choices: startModelChoices,
                        selectedID: $preferredFirstModelID,
                        displayName: selectedModelDisplayName,
                        isPlaceholder: !didPickStartModel && preferredFirstModelID.isEmpty,
                        onSelection: { didPickStartModel = true }
                    )
                    .opacity(modelCardVisible ? 1 : 0)
                    .offset(y: modelCardVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.7), value: modelCardVisible)
                }
                .padding(.horizontal, 20)

                Spacer()

                Button {
                    onComplete()
                } label: {
                    Text("Loslegen")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 38)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().stroke(Color.white.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .opacity(footerVisible ? 1 : 0)
                .offset(y: footerVisible ? 0 : 8)
                .animation(.easeOut(duration: 0.8), value: footerVisible)
                .padding(.bottom, 28)
            }
        }
        .ignoresSafeArea()
        .onAppear { runChoreography() }
        .task { await refreshPermissionStates() }
        .alert("Mikrofon-Zugriff", isPresented: $showMicSettingsAlert) {
            Button("Einstellungen öffnen") { openSystemSettings() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Du kannst den Mikrofon-Zugriff nur in den iOS-Einstellungen ändern.")
        }
        .alert("Benachrichtigungen", isPresented: $showNotificationSettingsAlert) {
            Button("Einstellungen öffnen") { openSystemSettings() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Du kannst Benachrichtigungen nur in den iOS-Einstellungen ändern.")
        }
    }

    // MARK: - Permission bindings

    /// Custom binding that delegates to the iOS permission APIs on set.
    /// `get` returns the currently-known system state; `set` either
    /// triggers an async permission request (turning ON from OFF) or
    /// surfaces the "open iOS Settings" alert (any other transition,
    /// since code can't revoke a granted permission and iOS won't
    /// re-show the popup once the user has denied it).
    private var microphoneBinding: Binding<Bool> {
        Binding(
            get: { microphoneGranted },
            set: { requested in
                if requested {
                    Task { await requestMicrophonePermission() }
                } else {
                    showMicSettingsAlert = true
                }
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsGranted },
            set: { requested in
                if requested {
                    Task { await requestNotificationPermission() }
                } else {
                    showNotificationSettingsAlert = true
                }
            }
        )
    }

    // MARK: - Permission logic

    /// Seeds `microphoneGranted` and `notificationsGranted` from the
    /// real system state. Called on view-appear and after every
    /// `request*Permission` call so the toggles reflect reality.
    @MainActor
    private func refreshPermissionStates() async {
        microphoneGranted = (AVAudioApplication.shared.recordPermission == .granted)

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsGranted = true
        default:
            notificationsGranted = false
        }
    }

    /// Handles a tap that wants mic turned ON. Routes to either the
    /// native popup, an "open Settings" alert, or a no-op depending on
    /// the current authorisation state.
    @MainActor
    private func requestMicrophonePermission() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneGranted = true
        case .denied:
            microphoneGranted = false
            showMicSettingsAlert = true
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            microphoneGranted = granted
        @unknown default:
            microphoneGranted = false
        }
    }

    @MainActor
    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                notificationsGranted = granted
            } catch {
                notificationsGranted = false
            }
        case .denied:
            notificationsGranted = false
            showNotificationSettingsAlert = true
        case .authorized, .provisional, .ephemeral:
            notificationsGranted = true
        @unknown default:
            notificationsGranted = false
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Layers

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.10),
                Color(red: 0.04, green: 0.06, blue: 0.16),
                Color(red: 0.01, green: 0.02, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var ambientParticles: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let now = context.date.timeIntervalSinceReferenceDate
                let count = 14
                for i in 0..<count {
                    let phase = Double(i) * 1.7
                    let x = 0.5 + 0.45 * sin(now * 0.07 + phase)
                    let y = 0.5 + 0.45 * cos(now * 0.05 + phase * 1.4)
                    let r = 1.0 + Double((i * 13) % 5) * 0.3
                    let alpha = 0.10 + Double((i * 7) % 9) * 0.02
                    let cx = x * size.width
                    let cy = y * size.height
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Personalisieren")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.94))
                .tracking(0.3)
            Text("Kann später jederzeit geändert werden.")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.50))
                .tracking(0.2)
        }
        .frame(maxWidth: .infinity)
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : 8)
        .animation(.easeOut(duration: 0.9), value: headerVisible)
    }

    // MARK: - Choreography

    private func runChoreography() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { headerVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { micCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { notificationCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { cellularCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { modelCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { footerVisible = true }
    }
}

// MARK: - Card components

private struct Beat2SettingCard: View {
    let icon: String
    let title: String
    let desc: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                Text(desc)
                    .font(.system(size: 11.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color(red: 72.0/255, green: 154.0/255, blue: 255.0/255))
                .scaleEffect(0.82)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 120.0/255, green: 170.0/255, blue: 255.0/255).opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 150.0/255, green: 190.0/255, blue: 255.0/255))
        }
    }
}

private struct Beat2ModelCard: View {
    let choices: [ModelEntry]
    @Binding var selectedID: String
    let displayName: String
    /// True when the user hasn't yet picked an option. Renders the
    /// capsule label in a dimmed "placeholder" style so it's visually
    /// obvious the control needs attention.
    let isPlaceholder: Bool
    let onSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 120.0/255, green: 170.0/255, blue: 255.0/255).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "shippingbox")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 150.0/255, green: 190.0/255, blue: 255.0/255))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Wähle dein Startmodell aus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                Text("Dein erster lokaler Assistent. Später jederzeit änderbar.")
                    .font(.system(size: 11.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            Menu {
                Button {
                    selectedID = ""
                    onSelection()
                } label: {
                    HStack {
                        Text("Später wählen")
                        if selectedID.isEmpty {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(choices) { choice in
                    Button {
                        selectedID = choice.id
                        onSelection()
                    } label: {
                        HStack {
                            Text("\(choice.displayName) · \(String(format: "%.1f GB", choice.sizeGB))")
                            if choice.id == selectedID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(red: 120.0/255, green: 170.0/255, blue: 255.0/255)
                            .opacity(isPlaceholder ? 0.08 : 0.16))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(red: 120.0/255, green: 170.0/255, blue: 255.0/255)
                            .opacity(isPlaceholder ? 0.18 : 0.30), lineWidth: 1)
                )
                .foregroundStyle(Color(red: 180.0/255, green: 210.0/255, blue: 255.0/255)
                    .opacity(isPlaceholder ? 0.55 : 1.0))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

#Preview {
    Beat2EinstellungenView(onComplete: {})
        .preferredColorScheme(.dark)
}
