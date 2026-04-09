//
//  Beat2EinstellungenView.swift
//  Lokalo
//
//  Second beat of the onboarding flow. Two iOS-style settings cards: a
//  cellular-downloads toggle and a model picker for the suggested first
//  model. The user's choices are persisted to UserDefaults via @AppStorage
//  and the keys in `OnboardingPreferences`. After "Loslegen", the parent
//  flow flips `hasCompletedOnboarding` and the chat view becomes the root.
//

import SwiftUI

struct Beat2EinstellungenView: View {
    let onComplete: () -> Void

    @AppStorage(OnboardingPreferences.cellularDownloadsAllowedKey)
    private var cellularAllowed: Bool = false

    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID

    @State private var headerVisible = false
    @State private var cellularCardVisible = false
    @State private var modelCardVisible = false
    @State private var footerVisible = false

    /// Three smallest phone-compatible models, sorted ascending. Used by the
    /// model-picker menu so the user picks among the genuinely tiny ones.
    private var smallModelChoices: [ModelEntry] {
        ModelCatalog.phoneCompatible
            .sorted { $0.sizeBytes < $1.sizeBytes }
            .prefix(4)
            .map { $0 }
    }

    private var selectedModelDisplayName: String {
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
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Modelle ohne WLAN laden",
                        desc: "Standardmäßig nur über WLAN — sind oft 1–4 GB.",
                        isOn: $cellularAllowed
                    )
                    .opacity(cellularCardVisible ? 1 : 0)
                    .offset(y: cellularCardVisible ? 0 : 10)
                    .animation(.easeOut(duration: 0.7), value: cellularCardVisible)

                    Beat2ModelCard(
                        choices: smallModelChoices,
                        selectedID: $preferredFirstModelID,
                        displayName: selectedModelDisplayName
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { cellularCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) { modelCardVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.50) { footerVisible = true }
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
                Text("Empfohlenes Modell")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                Text("Wird beim ersten Start hervorgehoben.")
                    .font(.system(size: 11.5, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            Menu {
                Button {
                    selectedID = ""
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
                        .fill(Color(red: 120.0/255, green: 170.0/255, blue: 255.0/255).opacity(0.16))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(red: 120.0/255, green: 170.0/255, blue: 255.0/255).opacity(0.30), lineWidth: 1)
                )
                .foregroundStyle(Color(red: 180.0/255, green: 210.0/255, blue: 255.0/255))
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
