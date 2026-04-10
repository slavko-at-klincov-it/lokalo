//
//  RootView.swift
//  Lokal
//
//  Top-level container after onboarding completes. Hosts four tabs
//  (Chat, Modelle, Wissen, Einstellungen) switched via the custom
//  `MainTabBar` floating pill. Each tab owns its own NavigationStack
//  (or reuses the internal one inside the tab's root view, in the
//  case of Knowledge and Settings) so back-stack state is preserved
//  independently when switching tabs.
//
//  The floating tab bar is installed via `.safeAreaInset(edge:)` so
//  content above it (scroll views, forms, chat message lists) never
//  underflows the bar — the tab bar becomes part of the content's
//  safe area and pushes content up cleanly.
//
//  Cross-tab crossfade: the content ZStack animates between branches
//  via `.transition(.opacity)` with a short `.easeInOut`, so tabs
//  never appear to "jump". Active tab state + cross fade share the
//  same animation block, so the tab-bar visual feedback and the
//  content swap feel like one gesture.
//

import SwiftUI

struct RootView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(ChatStore.self) private var chatStore

    @State private var selectedTab: MainTab = .chat

    /// One navigation path per tab. SwiftUI re-uses the same
    /// NavigationStack instance per tab branch, so pushed views
    /// remain on the stack when the user jumps to another tab
    /// and back.
    @State private var chatPath = NavigationPath()
    @State private var modelsPath = NavigationPath()

    @AppStorage(OnboardingPreferences.preferredFirstModelIDKey)
    private var preferredFirstModelID: String = OnboardingPreferences.defaultFirstModelID
    @AppStorage(OnboardingPreferences.hasCompletedKey)
    private var hasCompletedOnboarding: Bool = false
    @State private var didShowPreferredFirstModel = false
    @State private var showLowRAMWarning = false

    /// Soft taptic for tab changes — same style as the paging
    /// commit and Loslegen impact. `prepare()` in `.task` avoids
    /// cold-start latency on the first tap.
    private let tabHaptic = UIImpactFeedbackGenerator(style: .soft)

    @Environment(\.colorScheme) private var colorScheme

    /// True while the system software keyboard is on screen. Drives
    /// the tab-bar hide/show animation — a keyboard + floating tab
    /// bar + composer row eats almost half the vertical space on
    /// an iPhone, so we get rid of the tab bar while the user is
    /// typing and bring it back the moment the keyboard dismisses.
    @State private var isKeyboardVisible: Bool = false

    /// Explicit space reserved at the bottom of `tabContent` for the
    /// floating `MainTabBar`. We used to reserve this via an outer
    /// `.safeAreaInset`, but SwiftUI fails to propagate that inset
    /// through the per-tab `NavigationStack` in iOS 17/18 — the
    /// inner ChatView composer was rendering BEHIND the tab bar
    /// because it saw a full-screen bottom instead of a
    /// tab-bar-adjusted one. Explicit padding sidesteps the
    /// propagation bug entirely.
    ///
    /// Value = visible pill height (~52 pt) minus the tab-bar's
    /// downward `offset(y:)` (20 pt) so the composer hugs right up
    /// against the top of the visually-lowered pill instead of
    /// floating with an empty 20 pt gap above it.
    private let tabBarReservedHeight: CGFloat = 52

    /// How far to shove the tab-bar pill down into the home-indicator
    /// safe area. 20 pt puts the pill's bottom edge right next to
    /// the home-indicator stroke without overlapping it, which
    /// maximises the usable vertical space above while keeping tap
    /// targets outside the swipe-to-home gesture-critical strip
    /// (bottom ~10 pt).
    private let tabBarBottomOffset: CGFloat = 20

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dark-mode base layer: the Lokalo gradient sits behind
            // the tab content, so transparent child views (ChatView
            // message list, ScrollView-backed detail pages) inherit
            // the dark-blue aesthetic for free. In light mode this
            // is a no-op and the tab content's native iOS background
            // shows through.
            if colorScheme == .dark {
                DarkBlueGradient()
            }

            tabContent
                .transition(.opacity)
                .id(selectedTab)
                // Explicit reserved space for the tab bar. Because
                // this padding is applied *here* (not via an outer
                // safeAreaInset), every child view — including
                // ChatView's composer inside a NavigationStack —
                // honors it regardless of SwiftUI's inset
                // propagation quirks. When the keyboard is up the
                // tab bar is hidden, so we drop the reservation to
                // zero and let the keyboard safe area push the
                // composer up directly.
                .padding(.bottom, isKeyboardVisible ? 0 : tabBarReservedHeight)

            if !isKeyboardVisible {
                MainTabBar(selectedTab: $selectedTab) { newTab in
                    tabHaptic.impactOccurred(intensity: 0.55)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        selectedTab = newTab
                    }
                }
                .offset(y: tabBarBottomOffset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: isKeyboardVisible)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            isKeyboardVisible = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            isKeyboardVisible = false
        }
        .task(id: modelStore.activeID) {
            await chatStore.ensureEngineLoaded()
        }
        .task {
            tabHaptic.prepare()

            // RAM check: warn once if the device has less than 8 GB.
            // 3B+ models need ~2.5–3 GB of inference RAM; on 6 GB
            // devices the iOS Jetsam limit (~3 GB) is too tight for
            // a stable experience. Apple Intelligence draws the same
            // line — 8 GB minimum.
            let physicalRAM = ProcessInfo.processInfo.physicalMemory
            if physicalRAM < 7_500_000_000 { // < ~7.5 GB (8 GB devices report ~7.9 GB)
                showLowRAMWarning = true
            }

            // Wait long enough for (a) `modelStore.bootstrap()` to
            // finish and (b) the onboarding → RootView scale+fade
            // spring to settle, before pushing into the preferred
            // model detail. Pushing mid-transition causes a visible
            // collision between the LokalApp transition and the
            // NavigationStack push.
            try? await Task.sleep(nanoseconds: 950_000_000)
            presentPreferredFirstModelIfNeeded()
        }
        .alert("Nicht genügend Arbeitsspeicher", isPresented: $showLowRAMWarning) {
            Button("Trotzdem verwenden") { }
        } message: {
            Text("Lokalo benötigt mindestens 8 GB RAM für eine stabile Erfahrung. Auf diesem Gerät können größere Modelle zu Abstürzen führen. Kleine Modelle (0,5–1,5 B) funktionieren möglicherweise trotzdem.")
        }
        .onChange(of: hasCompletedOnboarding) { _, _ in
            presentPreferredFirstModelIfNeeded()
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .chat:
            NavigationStack(path: $chatPath) {
                Group {
                    if modelStore.hasInstalledModels {
                        ChatView(path: $chatPath)
                    } else {
                        ChatEmptyState(onGoToModels: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                selectedTab = .models
                            }
                        })
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    destination(for: route, path: $chatPath)
                }
            }

        case .models:
            NavigationStack(path: $modelsPath) {
                LibraryView(path: $modelsPath)
                    .navigationDestination(for: Route.self) { route in
                        destination(for: route, path: $modelsPath)
                    }
            }

        case .knowledge:
            // `KnowledgeView` provides its own NavigationStack, so
            // we drop it in as-is — nested NavigationStacks cause
            // layout bugs in SwiftUI 17.
            KnowledgeView()

        case .settings:
            // `SettingsSheet` also has its own NavigationStack;
            // passing `showsDismiss: false` hides the "Fertig"
            // button that only makes sense when presented as a sheet.
            SettingsSheet(showsDismiss: false)
        }
    }

    @ViewBuilder
    private func destination(for route: Route, path: Binding<NavigationPath>) -> some View {
        switch route {
        case .library:
            LibraryView(path: path)
        case .modelDetail(let id):
            if let entry = ModelCatalog.entry(id: id) {
                ModelDetailView(entry: entry, path: path)
            } else {
                Text("Modell nicht gefunden")
            }
        }
    }

    // MARK: - Preferred-first-model one-shot

    /// Right after the user finishes onboarding, if they picked a
    /// preferred first model and don't have any model installed yet,
    /// jump to the Modelle tab and push the detail view so they see
    /// the "Herunterladen" button immediately. The flag prevents
    /// re-pushing on every render.
    private func presentPreferredFirstModelIfNeeded() {
        guard hasCompletedOnboarding,
              !didShowPreferredFirstModel,
              !modelStore.hasInstalledModels,
              ModelCatalog.entry(id: preferredFirstModelID) != nil
        else {
            return
        }
        didShowPreferredFirstModel = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            selectedTab = .models
        }
        modelsPath.append(Route.modelDetail(preferredFirstModelID))
    }
}

enum Route: Hashable {
    case library
    case modelDetail(String)
}

/// Empty state shown in the Chat tab when no model is installed.
/// Gently nudges the user toward the Modelle tab where they can
/// pick and download one. The `RootView` ZStack already draws the
/// `DarkBlueGradient` behind us in dark mode, so this view stays
/// transparent and the gradient shows through. In light mode the
/// view simply sits on the default iOS background.
private struct ChatEmptyState: View {
    let onGoToModels: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(Color.primary.opacity(0.55))

                VStack(spacing: 6) {
                    Text("Noch kein Modell")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .tracking(0.3)
                    Text("Wechsle zu Modelle und lade dir\neinen lokalen Assistenten aufs Gerät.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .tracking(0.15)
                }

                Button {
                    onGoToModels()
                } label: {
                    Text("Zu Modelle")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .padding(.horizontal, 34)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().stroke(Color.primary.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }
}
