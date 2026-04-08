//
//  MCPServerListView.swift
//  Lokal
//
//  Manage Streamable HTTP MCP servers (no stdio on iOS).
//

import SwiftUI

struct MCPServerListView: View {
    @Environment(MCPStore.self) private var store
    @State private var showAdd = false
    @State private var editing: MCPServerConfig?

    var body: some View {
        List {
            Section {
                Text("MCP-Server (Model Context Protocol) erweitern Lokalo um Tools wie Web-Suche oder andere Datenquellen. Lokalo unterstützt nur **Streamable HTTP** MCP-Server — Stdio-Server (z.B. die meisten in `npx`) funktionieren auf iOS nicht.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if store.servers.isEmpty {
                Section {
                    Text("Noch keine Server eingerichtet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Server") {
                    ForEach(store.servers) { server in
                        serverRow(server)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            store.remove(store.servers[i].id)
                        }
                    }
                }
            }
        }
        .navigationTitle("MCP-Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMCPServerSheet()
        }
        .sheet(item: $editing) { server in
            AddMCPServerSheet(existing: server)
        }
    }

    @ViewBuilder
    private func serverRow(_ server: MCPServerConfig) -> some View {
        let state = store.connectionStatus[server.id] ?? .disconnected
        Button {
            editing = server
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(server.name).font(.subheadline.weight(.medium))
                    Spacer()
                    statusBadge(state)
                }
                Text(server.endpoint.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case .error(let msg) = state {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
                HStack(spacing: 10) {
                    if state == .connected {
                        Button("Trennen") {
                            Task { await store.disconnect(server) }
                        }
                        .font(.caption)
                    } else {
                        Button("Verbinden") {
                            Task { await store.connect(server) }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(_ state: MCPStore.ConnectionState) -> some View {
        switch state {
        case .connected:
            Text("verbunden")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        case .connecting:
            ProgressView().controlSize(.mini)
        case .disconnected:
            Text("getrennt")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
        case .error:
            Text("fehler")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)
        }
    }
}

struct AddMCPServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MCPStore.self) private var store

    @State private var name: String = ""
    @State private var endpoint: String = "https://"
    @State private var bearerToken: String = ""
    @State private var enabled: Bool = true
    @State private var requiresAuth: Bool = false

    private let existing: MCPServerConfig?

    init(existing: MCPServerConfig? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("Endpoint URL", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Aktiviert", isOn: $enabled)
                }
                Section("Authentifizierung") {
                    Toggle("Bearer Token erforderlich", isOn: $requiresAuth)
                    if requiresAuth {
                        SecureField("Bearer Token", text: $bearerToken)
                    }
                }
                Section {
                    Button(isValid ? "Speichern" : "Bitte Pflichtfelder ausfüllen") {
                        save()
                    }
                    .disabled(!isValid)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(existing == nil ? "Neuer MCP-Server" : "Server bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    endpoint = existing.endpoint.absoluteString
                    enabled = existing.enabled
                    requiresAuth = existing.requiresAuth
                    bearerToken = store.token(for: existing.id) ?? ""
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: endpoint.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
    }

    private func save() {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else { return }
        if let existing {
            var updated = existing
            updated.name = name
            updated.endpoint = url
            updated.enabled = enabled
            updated.requiresAuth = requiresAuth
            store.update(updated, bearerToken: requiresAuth ? bearerToken : "")
        } else {
            let cfg = MCPServerConfig(
                name: name,
                endpoint: url,
                enabled: enabled,
                requiresAuth: requiresAuth
            )
            store.add(cfg, bearerToken: requiresAuth ? bearerToken : nil)
        }
        dismiss()
    }
}
