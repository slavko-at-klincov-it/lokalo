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
    /// True when this view is the currently-visible onboarding page.
    /// `OnboardingFlow` passes `currentBeat == 1` here. Because Beat 2
    /// now lives in a horizontal HStack next to Beat 1 (for interactive
    /// paging), it's mounted from app launch — its `.onAppear` fires
    /// while the user is still on Beat 1, so we can't use `onAppear`
    /// to trigger the card-reveal choreography any more. Instead, the
    /// view watches `isActive` and starts the staggered fade-in the
    /// moment the user commits the swipe.
    let isActive: Bool
    let onComplete: () -> Void

    init(isActive: Bool = true, onComplete: @escaping () -> Void) {
        self.isActive = isActive
        self.onComplete = onComplete
    }

    /// The current system color scheme — read from the environment,
    /// set by `LokalApp.preferredColorScheme` which itself reflects
    /// the user's `AppearanceMode` AppStorage preference. Drives
    /// the adaptive background + particle color in this view.
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(OnboardingPreferences.cellularDownloadsAllowedKey)
    private var cellularAllowed: Bool = false

    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID

    /// Dark / Light theme selection. Bound to the same AppStorage key
    /// that `LokalApp.preferredColorScheme` reads, so tapping one of
    /// the two preview capsules re-skins the whole app instantly.
    @AppStorage(OnboardingPreferences.appearanceModeKey)
    private var appearanceModeRaw: String = OnboardingPreferences.defaultAppearanceMode.rawValue

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
    @State private var themeCardVisible = false
    @State private var footerVisible = false

    /// One-shot guard so the staggered reveal only runs once, even if
    /// `isActive` somehow toggles back-and-forth.
    @State private var hasChoreographed = false

    /// Soft taptic for the "Loslegen" tap — shares the same style as
    /// the paging-commit haptic in `OnboardingFlow`, so the whole
    /// onboarding gesture vocabulary feels like one instrument.
    /// Prepared in `.onAppear` to avoid cold-start latency.
    private let loslegenHaptic = UIImpactFeedbackGenerator(style: .soft)

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

                    Beat2ThemeCard(
                        selectedMode: Binding(
                            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .dark },
                            set: { appearanceModeRaw = $0.rawValue }
                        )
                    )
                    .opacity(themeCardVisible ? 1 : 0)
                    .offset(y: themeCardVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.7), value: themeCardVisible)
                }
                .padding(.horizontal, 20)

                Spacer()

                Button {
                    loslegenHaptic.impactOccurred(intensity: 0.8)
                    onComplete()
                } label: {
                    Text("Loslegen")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.primary.opacity(0.92))
                        .padding(.horizontal, 38)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().stroke(Color.primary.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(LoslegenPressStyle())
                .opacity(footerVisible ? 1 : 0)
                .offset(y: footerVisible ? 0 : 8)
                .animation(.easeOut(duration: 0.8), value: footerVisible)
                .padding(.bottom, 28)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Warm up the taptic engine so the first Loslegen impact
            // fires with zero latency — without this, the first haptic
            // has a 80-200 ms cold-start lag that feels like a bug.
            loslegenHaptic.prepare()
            // Start the staggered card reveal only if we're already
            // the active page (e.g. SwiftUI previews construct Beat 2
            // directly with the default `isActive: true`). In the
            // real onboarding flow, this fires early while the user
            // is still on Beat 1, so `isActive == false` and the
            // choreography waits for the `onChange` below.
            if isActive { runChoreography() }
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive { runChoreography() }
        }
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
        ThemedOnboardingBackground()
    }

    private var ambientParticles: some View {
        // Canvas contexts don't resolve SwiftUI semantic colors
        // (`.primary`, etc.) automatically — we have to pass a
        // concrete colour. Pick white on dark backgrounds, near-black
        // on light backgrounds, so the drifting particles stay
        // visible in both themes.
        let particleBase: Color = colorScheme == .dark ? .white : Color(white: 0.10)
        return TimelineView(.animation) { context in
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
                    ctx.fill(Path(ellipseIn: rect), with: .color(particleBase.opacity(alpha)))
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
                .foregroundStyle(.primary.opacity(0.94))
                .tracking(0.3)
            Text("Kann später jederzeit geändert werden.")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.primary.opacity(0.50))
                .tracking(0.2)
        }
        .frame(maxWidth: .infinity)
        .opacity(headerVisible ? 1 : 0)
        .offset(y: headerVisible ? 0 : 8)
        .animation(.easeOut(duration: 0.9), value: headerVisible)
    }

    // MARK: - Choreography

    /// Staggered card reveal, fired once when `isActive` first flips
    /// true. Delays are absolute from t=0 (the moment of commit) —
    /// the first element (header) appears ~0.3 s in, giving the
    /// page-slide spring time to mostly settle before the cards
    /// start fading in, so the two motions don't fight each other
    /// visually.
    private func runChoreography() {
        guard !hasChoreographed else { return }
        hasChoreographed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { headerVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { micCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { notificationCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { cellularCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { modelCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { themeCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) { footerVisible = true }
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
                    .foregroundStyle(.primary.opacity(0.94))
                Text(desc)
                    .font(.system(size: 11.5, weight: .light))
                    .foregroundStyle(.primary.opacity(0.55))
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
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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
                    .foregroundStyle(.primary.opacity(0.94))
                Text("Dein erster lokaler Assistent. Später jederzeit änderbar.")
                    .font(.system(size: 11.5, weight: .light))
                    .foregroundStyle(.primary.opacity(0.55))
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
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct Beat2ThemeCard: View {
    @Binding var selectedMode: AppearanceMode

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 120.0 / 255, green: 170.0 / 255, blue: 255.0 / 255).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 150.0 / 255, green: 190.0 / 255, blue: 255.0 / 255))
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erscheinungsbild")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.94))
                    Text("Kann jederzeit in den Einstellungen geändert werden.")
                        .font(.system(size: 11.5, weight: .light))
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    ForEach(AppearanceMode.allCases) { mode in
                        ThemePreviewCapsule(
                            mode: mode,
                            isActive: selectedMode == mode
                        ) {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                selectedMode = mode
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

/// A single preview capsule used inside `Beat2ThemeCard`. Each
/// capsule renders a miniature of the theme it represents — dark
/// capsule for Dark mode (mini dark-blue gradient + moon icon),
/// light capsule for Light mode (flat light background + sun
/// icon). The active capsule gets a soft-blue stroke and full
/// opacity; the inactive one fades back to 45%.
private struct ThemePreviewCapsule: View {
    let mode: AppearanceMode
    let isActive: Bool
    let onTap: () -> Void

    private let accent = Color(red: 120.0 / 255, green: 170.0 / 255, blue: 255.0 / 255)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 11, weight: .medium))
                Text(mode.label.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
            }
            .foregroundStyle(capsuleForeground)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: capsuleFill,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isActive ? accent.opacity(0.60) : Color.primary.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(LoslegenPressStyle())
    }

    /// Two-colour gradient fill for the capsule interior — picks the
    /// Lokalo dark blue for the Dark capsule and an opaque near-white
    /// for the Light capsule. The colours are intentionally *fixed*
    /// regardless of the global appearance mode, because each capsule
    /// is previewing a specific theme — the Dark capsule must look
    /// dark even when the whole app is in light mode, and vice versa.
    private var capsuleFill: [Color] {
        switch mode {
        case .dark:
            return [
                Color(red: 0.03, green: 0.05, blue: 0.12),
                Color(red: 0.01, green: 0.02, blue: 0.06)
            ]
        case .light:
            return [
                Color(white: 0.98),
                Color(white: 0.92)
            ]
        }
    }

    /// Foreground colour for the capsule's icon + label. Locked to
    /// the capsule's own mode (white on the dark capsule, near-black
    /// on the light capsule) so the label is always legible against
    /// the matching capsule fill, regardless of the surrounding
    /// theme. Active capsules get 0.94 opacity, inactive 0.45.
    private var capsuleForeground: Color {
        let base: Color = (mode == .dark) ? .white : Color(white: 0.10)
        return base.opacity(isActive ? 0.94 : 0.45)
    }
}

/// Custom press style for the "Loslegen" button: a subtle 0.94 scale
/// with a snappy interpolating spring. Gives the tap physical weight
/// without leaving the button looking "held down" for long. Stiffness
/// 420 settles in ~0.18 s, so the release-back is almost instant and
/// doesn't fight with the outer page-dismissal spring.
private struct LoslegenPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(
                .interpolatingSpring(stiffness: 420, damping: 22),
                value: configuration.isPressed
            )
    }
}

#Preview {
    Beat2EinstellungenView(onComplete: {})
        .preferredColorScheme(.dark)
}
