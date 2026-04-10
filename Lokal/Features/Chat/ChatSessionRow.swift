//
//  ChatSessionRow.swift
//  Lokal
//
//  Single row in the chat drawer. Shows the session title, a one-line
//  preview of the last message, the model used by this chat and a relative
//  timestamp. Active sessions are marked with a small accent dot.
//

import SwiftUI

struct ChatSessionRow: View {

    let session: ChatSession
    let isActive: Bool
    /// Name of the currently-loaded chat model. Used so the row can mark its
    /// model badge in accent color when the session's model matches the
    /// currently-loaded one — a subtle cue that this row will open
    /// instantly, without triggering the "Modell laden?" gate.
    let currentlyLoadedModelID: String?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            activeDot
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: .now))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !session.lastMessagePreview.isEmpty {
                    Text(session.lastMessagePreview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                badgeRow
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var activeDot: some View {
        Circle()
            .fill(isActive ? Color.accentColor : Color.clear)
            .frame(width: 8, height: 8)
            .padding(.top, 6)
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 6) {
            modelBadge
            if session.knowledgeBaseID != nil {
                ragBadge
            }
        }
    }

    private var modelBadge: some View {
        let isLoaded = currentlyLoadedModelID == session.chatModelID
        let name = ModelCatalog.entry(id: session.chatModelID)?.displayName ?? session.chatModelID
        return HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 9, weight: .semibold))
            Text(name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(isLoaded
                      ? Color.accentColor.opacity(0.15)
                      : Color.gray.opacity(0.15))
        )
        .foregroundStyle(isLoaded ? Color.accentColor : .secondary)
    }

    private var ragBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Wissen")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.15))
        )
        .foregroundStyle(Color.green)
    }
}
