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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(modelStore)
                .environment(downloadManager)
                .environment(chatStore)
                .preferredColorScheme(nil)
                .tint(.accentColor)
                .task {
                    FileLog.resetForLaunch()
                    FileLog.write("LokaloApp.task fired")
                    await modelStore.bootstrap()
                    FileLog.write("modelStore bootstrap done, installed=\(modelStore.installedModels.count)")
                    downloadManager.attach(modelStore: modelStore)
                    chatStore.attach(modelStore: modelStore)
                    await downloadManager.resumePending()
                    await chatStore.runAutoTestPromptIfPresent()
                }
        }
    }
}
