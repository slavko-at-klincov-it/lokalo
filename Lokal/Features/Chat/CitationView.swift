//
//  CitationView.swift
//  Lokal
//
//  Pill row that lists which knowledge-base chunks the assistant cited.
//

import SwiftUI

struct CitationRow: View {
    let citations: [Citation]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(citations) { citation in
                    CitationPill(citation: citation)
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct CitationPill: View {
    let citation: Citation
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            CitationDetailSheet(citation: citation)
        }
    }

    private var label: String {
        if let page = citation.pageIndex {
            return "\(citation.sourceName) · S. \(page + 1)"
        }
        return citation.sourceName
    }
}

struct CitationDetailSheet: View {
    let citation: Citation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let page = citation.pageIndex {
                        Text("Seite \(page + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(citation.snippet)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle(citation.sourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
