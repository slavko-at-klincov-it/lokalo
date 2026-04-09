//
//  LokalApp.swift
//  Lokalo — On-device AI. Nothing leaves your phone.
//

import SwiftUI

@main
struct LokalApp: App {
    // Build the entire dependency graph in one place. Each store takes its
    // dependencies in `init`, so the type system enforces the order and
    // forgetting one is a compile error — there is no `attach()` pattern
    // and no weak references to mutate at runtime.
    @State private var modelStore: ModelStore
    @State private var kbStore: KnowledgeBaseStore
    @State private var embeddingStore: EmbeddingModelStore
    @State private var connectionStore: ConnectionStore
    @State private var mcpStore: MCPStore
    @State private var downloadManager: DownloadManager
    @State private var embeddingDownloader: EmbeddingDownloader
    @State private var indexingService: IndexingService
    @State private var chatStore: ChatStore
    @State private var remoteCatalogService: RemoteCatalogService

    init() {
        let modelStore = ModelStore()
        let kbStore = KnowledgeBaseStore()
        let embeddingStore = EmbeddingModelStore()
        let connectionStore = ConnectionStore()
        let mcpStore = MCPStore()
        let remoteCatalogService = RemoteCatalogService()

        let downloadManager = DownloadManager(modelStore: modelStore)
        let embeddingDownloader = EmbeddingDownloader(store: embeddingStore)
        let indexingService = IndexingService(
            kbStore: kbStore,
            embeddingStore: embeddingStore,
            connectionStore: connectionStore
        )
        let chatStore = ChatStore(
            modelStore: modelStore,
            kbStore: kbStore,
            indexingService: indexingService,
            mcpStore: mcpStore
        )

        _modelStore         = State(wrappedValue: modelStore)
        _kbStore            = State(wrappedValue: kbStore)
        _embeddingStore     = State(wrappedValue: embeddingStore)
        _connectionStore    = State(wrappedValue: connectionStore)
        _mcpStore           = State(wrappedValue: mcpStore)
        _downloadManager    = State(wrappedValue: downloadManager)
        _embeddingDownloader = State(wrappedValue: embeddingDownloader)
        _indexingService    = State(wrappedValue: indexingService)
        _chatStore          = State(wrappedValue: chatStore)
        _remoteCatalogService = State(wrappedValue: remoteCatalogService)
    }

    /// First-launch flag — when false, the OnboardingFlow runs before the
    /// chat experience is revealed. Persists across launches in UserDefaults.
    @AppStorage(OnboardingPreferences.hasCompletedKey)
    private var hasCompletedOnboarding: Bool = false

    /// User-selected appearance mode. Stored as a raw string so it can
    /// survive a schema change to `AppearanceMode`. Changes to this
    /// value instantly re-render the whole app with the new color
    /// scheme via the `.preferredColorScheme(...)` modifier below.
    @AppStorage(OnboardingPreferences.appearanceModeKey)
    private var appearanceModeRaw: String = OnboardingPreferences.defaultAppearanceMode.rawValue

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    RootView()
                        // Emerges from a clearly smaller (88%) state
                        // while crossfading in. The depth cue reads
                        // as "product stepping forward towards you".
                        // Scale is intentionally pronounced — 6% was
                        // too subtle to read as animation.
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.88, anchor: .center)
                                .combined(with: .opacity),
                            removal: .identity
                        ))
                } else {
                    OnboardingFlow {
                        // `.spring(response:dampingFraction:)` is the
                        // *bounded* spring — it settles exactly on
                        // target, which is what transitions need.
                        // `.interpolatingSpring` is unbounded and can
                        // leave transitions feeling instant because
                        // the target state latches immediately.
                        //
                        // response: 0.85 s period → transitions read
                        // as a deliberate event, not a jump-cut.
                        // dampingFraction: 0.88 → no bounce, just a
                        // confident settle.
                        withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                            hasCompletedOnboarding = true
                        }
                    }
                    // Recedes into the background (scale 1.0 → 0.88)
                    // while fading out. Source-recedes + destination-
                    // emerges = "onboarding stepping back so the
                    // product can step forward". Both scales match
                    // on purpose so the motions interlock.
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .scale(scale: 0.88, anchor: .center)
                            .combined(with: .opacity)
                    ))
                }
            }
            .environment(modelStore)
            .environment(downloadManager)
            .environment(chatStore)
            .environment(kbStore)
            .environment(embeddingStore)
            .environment(embeddingDownloader)
            .environment(indexingService)
            .environment(connectionStore)
            .environment(mcpStore)
            .environment(remoteCatalogService)
            .preferredColorScheme(currentAppearanceMode.colorScheme)
            .tint(.accentColor)
            .task {
                // The dependency graph is wired by `init`. This task only
                // runs the *async* bootstrap that needs to load disk state.
                FileLog.resetForLaunch()
                FileLog.write("LokaloApp.task fired")
                await modelStore.bootstrap()
                FileLog.write("modelStore bootstrap done, installed=\(modelStore.installedModels.count)")
                embeddingStore.bootstrap()
                kbStore.bootstrap()
                connectionStore.bootstrap()
                mcpStore.bootstrap()
                await downloadManager.resumePending()
                await mcpStore.connectAllEnabled()
                // Refresh the model catalog from the remote in the
                // background. The new catalog only takes effect on the
                // next app launch (ModelCatalog.manifest is loaded once
                // synchronously and held for the process lifetime), but
                // we still kick this off every launch so the cache stays
                // close to head-of-main.
                await remoteCatalogService.refresh()
                await chatStore.runAutoTestPromptIfPresent()
            }
        }
    }
}
