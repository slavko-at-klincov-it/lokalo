//
//  LokalApp.swift
//  Lokalo — On-device AI. Nothing leaves your phone.
//

import SwiftUI

@main
struct LokalApp: App {
    @State private var modelStore = ModelStore()
    @State private var downloadManager = DownloadManager()
    @State private var chatStore = ChatStore()
    @State private var kbStore = KnowledgeBaseStore()
    @State private var embeddingStore = EmbeddingModelStore()
    @State private var embeddingDownloader = EmbeddingDownloader()
    @State private var indexingService = IndexingService()
    @State private var connectionStore = ConnectionStore()
    @State private var mcpStore = MCPStore()

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
                FileLog.resetForLaunch()
                FileLog.write("LokaloApp.task fired")
                await modelStore.bootstrap()
                FileLog.write("modelStore bootstrap done, installed=\(modelStore.installedModels.count)")
                embeddingStore.bootstrap()
                kbStore.bootstrap()
                connectionStore.bootstrap()
                mcpStore.bootstrap()
                downloadManager.attach(modelStore: modelStore)
                embeddingDownloader.attach(store: embeddingStore)
                indexingService.attach(
                    kbStore: kbStore,
                    embeddingStore: embeddingStore,
                    connectionStore: connectionStore
                )
                chatStore.attach(modelStore: modelStore)
                chatStore.attach(
                    kbStore: kbStore,
                    indexingService: indexingService,
                    mcpStore: mcpStore
                )
                await downloadManager.resumePending()
                await mcpStore.connectAllEnabled()
                await chatStore.runAutoTestPromptIfPresent()
            }
        }
    }
}
