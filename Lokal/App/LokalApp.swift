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

    init() {
        let modelStore = ModelStore()
        let kbStore = KnowledgeBaseStore()
        let embeddingStore = EmbeddingModelStore()
        let connectionStore = ConnectionStore()
        let mcpStore = MCPStore()

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
    }

    /// First-launch flag — when false, the OnboardingFlow runs before the
    /// chat experience is revealed. Persists across launches in UserDefaults.
    @AppStorage(OnboardingPreferences.hasCompletedKey)
    private var hasCompletedOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    RootView()
                        .transition(.opacity)
                } else {
                    OnboardingFlow {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            hasCompletedOnboarding = true
                        }
                    }
                    .transition(.opacity)
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
            .preferredColorScheme(nil)
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
                await chatStore.runAutoTestPromptIfPresent()
            }
        }
    }
}
