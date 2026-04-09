//
//  MainTabBar.swift
//  Lokal
//
//  Custom floating tab bar for Lokalo's primary navigation. Designed
//  as a "control surface" that complements the ultra-light wordmark
//  and dark-gradient aesthetic of the onboarding flow — this is not
//  a generic iOS UITabBar.
//
//  Shape: a rounded rectangle (corner radius 28) floating ~12 pt
//  above the home indicator with ~16 pt horizontal margins. Backed
//  by `.ultraThinMaterial` so content visible behind it shimmers
//  through subtly. Inner stroke (`white.opacity(0.12)`) and a soft
//  drop shadow give it the weight of a physical object.
//
//  Typography: 9 pt uppercase labels with 1.2 tracking + .medium
//  weight. SF Symbols in `.light` weight (20 pt) to match the
//  ultra-thin "Lokalo" wordmark from Beat 1.
//
//  Active state: two cooperating signals — the SF Symbol flips to
//  its `.fill` variant, and a 3 pt accent-blue dot appears above
//  the icon. Both fade in together with the tab switch spring, so
//  the visual commit feels decisive without needing an explicit
//  sliding indicator.
//
//  Motion: `.spring(response: 0.35, dampingFraction: 0.86)` on the
//  `selectedTab` state change drives the icon filled/dot opacity
//  crossfade. A soft taptic impact fires the moment the user taps
//  a different tab (matches the paging-commit and Loslegen haptics
//  so the entire app speaks one haptic language).
//

import SwiftUI

enum MainTab: CaseIterable, Hashable {
    case chat
    case models
    case knowledge
    case settings

    var systemIcon: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right"
        case .models:    return "shippingbox"
        case .knowledge: return "book"
        case .settings:  return "gearshape"
        }
    }

    var systemIconFilled: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right.fill"
        case .models:    return "shippingbox.fill"
        case .knowledge: return "book.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .chat:      return "Chat"
        case .models:    return "Modelle"
        case .knowledge: return "Wissen"
        case .settings:  return "Einstellungen"
        }
    }
}

struct MainTabBar: View {
    @Binding var selectedTab: MainTab
    let onTabSelected: (MainTab) -> Void

    /// Accent blue reused from `Beat2EinstellungenView` / `Beat2SettingCard`
    /// so the tab bar feels like a piece of the same system, not an
    /// afterthought painted with a different palette.
    private let accent = Color(red: 120.0 / 255, green: 170.0 / 255, blue: 255.0 / 255)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                MainTabBarButton(
                    tab: tab,
                    isActive: selectedTab == tab,
                    accent: accent
                ) {
                    guard selectedTab != tab else { return }
                    onTabSelected(tab)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 22, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

private struct MainTabBarButton: View {
    let tab: MainTab
    let isActive: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                // Active indicator — a 3 pt accent-blue dot that
                // fades in above the icon when the tab is selected.
                // Keeps the "you are here" signal quiet but definite.
                Circle()
                    .fill(accent)
                    .frame(width: 3, height: 3)
                    .opacity(isActive ? 1 : 0)
                    .scaleEffect(isActive ? 1 : 0.4)

                Image(systemName: isActive ? tab.systemIconFilled : tab.systemIcon)
                    .font(.system(size: 20, weight: .light))
                    .frame(height: 22)
                    .contentTransition(.symbolEffect(.replace))

                Text(tab.label)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(
                isActive
                    ? Color.white.opacity(0.94)
                    : Color.white.opacity(0.45)
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MainTabBarButtonStyle())
    }
}

/// Press style for the tab buttons — a subtle 0.92 scale with a
/// snappy spring. Gives the tap a physical anchor without pulling
/// focus from the content area.
private struct MainTabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                .interpolatingSpring(stiffness: 480, damping: 24),
                value: configuration.isPressed
            )
    }
}
