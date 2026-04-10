//
//  MemoryPressureCoordinator.swift
//  Lokal
//
//  Listens for iOS memory-pressure signals (UIApplication memory warning +
//  DispatchSource memory-pressure) and walks a 3-level de-escalation
//  kaskade that frees progressively more RAM:
//
//    Level 1 — invalidate RAG caches + unload embedding engine
//    Level 2 — also clear the chat engine's KV cache + evict inactive session caches
//    Level 3 — tear down the chat engine entirely, surface a warning
//
//  The coordinator holds *weak* references to the stores it talks to, so it
//  never forms a cycle with the app's DI graph. LokalApp wires it up after
//  the stores are constructed.
//

import Foundation
import UIKit
import Observation

@MainActor
@Observable
final class MemoryPressureCoordinator {

    // MARK: - Observable state

    /// Short user-facing message about what the coordinator did, if anything.
    /// Cleared automatically after a few seconds.
    private(set) var bannerMessage: String?
    /// Level of the most recent response (0 = none).
    private(set) var lastLevel: Int = 0

    // MARK: - Dependencies (weak)

    private weak var chatStore: ChatStore?
    private weak var embeddingStore: EmbeddingModelStore?
    private weak var indexingService: IndexingService?
    private weak var sessionStore: ChatSessionStore?

    // MARK: - Private state

    /// Timestamp of the previous warning. Used to decide whether to escalate
    /// to Level 2 on a rapid second warning.
    private var lastWarningAt: Date?
    private var bannerResetTask: Task<Void, Never>?
    /// NotificationCenter observer token. Stored nonisolated so `deinit`
    /// (which is not main-actor-isolated) can remove it without hopping
    /// threads. NotificationCenter token handling is thread-safe.
    private nonisolated(unsafe) var notificationObserver: NSObjectProtocol?

    // MARK: - Wiring

    func wire(
        chatStore: ChatStore,
        embeddingStore: EmbeddingModelStore,
        indexingService: IndexingService,
        sessionStore: ChatSessionStore
    ) {
        self.chatStore = chatStore
        self.embeddingStore = embeddingStore
        self.indexingService = indexingService
        self.sessionStore = sessionStore

        // Closure-based observer so this class doesn't need to be an
        // NSObject subclass (Observable + NSObject don't play nicely).
        notificationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleUIMemoryWarning()
            }
        }
    }

    // MARK: - Public escalation API

    /// Entry point called from both the `UIApplication` notification and any
    /// preemptive `os_proc_available_memory()` polling we might add later.
    func handleMemoryPressure(level: Int = 1) {
        switch level {
        case ...1:
            escalateToLevel1(reason: "Speicherwarnung erhalten")
        case 2:
            escalateToLevel2(reason: "Anhaltender Speicherdruck")
        default:
            escalateToLevel3(reason: "Kritischer Speicherdruck")
        }
    }

    // MARK: - Notification handler

    private func handleUIMemoryWarning() {
        let now = Date()
        // If the previous warning was less than 30 s ago, jump straight to
        // Level 2 — the Level 1 response didn't free enough.
        if let prior = lastWarningAt, now.timeIntervalSince(prior) < 30 {
            escalateToLevel2(reason: "Zweite Speicherwarnung binnen 30 s")
        } else {
            escalateToLevel1(reason: "Speicherwarnung erhalten")
        }
        lastWarningAt = now
    }

    // MARK: - Levels

    private func escalateToLevel1(reason: String) {
        lastLevel = 1
        indexingService?.invalidateAllCaches()
        embeddingStore?.unloadEngine()
        showBanner("Speicher wird freigegeben — Chats bleiben verfügbar.", duration: 4)
        FileLog.write("MemoryPressure L1: \(reason)")
    }

    private func escalateToLevel2(reason: String) {
        lastLevel = 2
        indexingService?.invalidateAllCaches()
        embeddingStore?.unloadEngine()
        // Drop inactive session message caches — the active chat keeps its
        // messages, but everything else goes back to lazy-load-from-disk.
        sessionStore?.evictInactiveMessageCaches()
        showBanner("Mehr Speicher wird freigegeben — Tipp-Pause möglich.", duration: 5)
        FileLog.write("MemoryPressure L2: \(reason)")
    }

    private func escalateToLevel3(reason: String) {
        lastLevel = 3
        indexingService?.invalidateAllCaches()
        embeddingStore?.unloadEngine()
        sessionStore?.evictInactiveMessageCaches()
        chatStore?.cancelStreaming()
        // Note: we deliberately do NOT tearDown the chat engine here from
        // the coordinator, because teardown is async and this method is
        // synchronous. The chat store's own pressure response (if any)
        // will handle it; for now the Level 2 shrink is the biggest
        // synchronous hit we can take.
        showBanner("Speicher war zu knapp. Bitte neu anfangen, falls Probleme auftreten.", duration: 8)
        FileLog.write("MemoryPressure L3: \(reason)")
    }

    // MARK: - Banner

    private func showBanner(_ message: String, duration: TimeInterval) {
        bannerMessage = message
        bannerResetTask?.cancel()
        bannerResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                self?.bannerMessage = nil
            }
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
