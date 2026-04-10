//
//  ChatDrawerView.swift
//  Lokal
//
//  Slide-in drawer that lists all chat sessions and lets the user switch
//  between them. Presented from the left edge of `ChatView` via ZStack +
//  offset + DragGesture — no UIKit, no .sheet.
//

import SwiftUI

struct ChatDrawerView: View {

    @Environment(ChatSessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelStore.self) private var modelStore

    /// Binding from the parent view. Set to false to dismiss the drawer.
    @Binding var isPresented: Bool

    /// Called when the user taps "Neue Unterhaltung" in the drawer header.
    /// Owned by the parent so it can close the drawer synchronously.
    var onCreateNew: () -> Void

    @State private var editingSessionID: UUID?
    @State private var editingTitle: String = ""
    @State private var sessionToDelete: UUID?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sessionStore.sessions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sortedSessions) { session in
                        rowView(for: session)
                            .listRowBackground(
                                (session.id == sessionStore.activeSessionID)
                                ? Color.accentColor.opacity(0.08)
                                : Color.clear
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { selectSession(session) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    requestDelete(session.id)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                contextMenu(for: session)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.regularMaterial)
        .alert("Chat umbenennen", isPresented: Binding(
            get: { editingSessionID != nil },
            set: { newValue in
                if !newValue {
                    editingSessionID = nil
                    editingTitle = ""
                }
            }
        )) {
            TextField("Titel", text: $editingTitle)
            Button("Speichern") {
                if let id = editingSessionID {
                    sessionStore.rename(id, title: editingTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                editingSessionID = nil
                editingTitle = ""
            }
            Button("Abbrechen", role: .cancel) {
                editingSessionID = nil
                editingTitle = ""
            }
        } message: {
            Text("Gib dem Chat einen neuen Titel.")
        }
        .confirmationDialog(
            "Diesen Chat löschen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let id = sessionToDelete {
                    sessionStore.delete(id)
                }
                sessionToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            Text("Der Verlauf wird unwiderruflich gelöscht.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Chat-Liste schließen")

            Text("Chats")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            Button {
                onCreateNew()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Neue Unterhaltung")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Noch keine Unterhaltungen")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Neue Unterhaltung") {
                onCreateNew()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(for session: ChatSession) -> some View {
        ChatSessionRow(
            session: session,
            isActive: session.id == sessionStore.activeSessionID,
            currentlyLoadedModelID: currentlyLoadedModelID
        )
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for session: ChatSession) -> some View {
        Button {
            startRename(session)
        } label: {
            Label("Umbenennen", systemImage: "pencil")
        }
        Button {
            duplicate(session)
        } label: {
            Label("Duplizieren", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) {
            requestDelete(session.id)
        } label: {
            Label("Löschen", systemImage: "trash")
        }
    }

    // MARK: - Sort

    private var sortedSessions: [ChatSession] {
        sessionStore.sessions.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private var currentlyLoadedModelID: String? {
        switch chatStore.loadState {
        case .ready(let id), .loading(let id, _), .unloading(let id):
            return id
        default:
            return modelStore.activeID
        }
    }

    // MARK: - Actions

    private func selectSession(_ session: ChatSession) {
        ChatHaptics.rowSelect()
        guard session.id != sessionStore.activeSessionID else {
            // Already active — just close the drawer.
            withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
                isPresented = false
            }
            return
        }
        chatStore.switchActiveSession(to: session.id)
        withAnimation(.interpolatingSpring(stiffness: 380, damping: 32)) {
            isPresented = false
        }
    }

    private func startRename(_ session: ChatSession) {
        editingSessionID = session.id
        editingTitle = session.displayTitle == "Neue Unterhaltung" ? "" : session.displayTitle
    }

    private func duplicate(_ session: ChatSession) {
        if let copy = sessionStore.duplicate(session.id) {
            sessionStore.setActive(copy.id)
        }
    }

    private func requestDelete(_ id: UUID) {
        sessionToDelete = id
        showDeleteConfirm = true
    }
}
