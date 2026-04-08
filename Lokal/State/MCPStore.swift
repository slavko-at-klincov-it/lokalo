//
//  MCPStore.swift
//  Lokal
//
//  Persists MCP server configurations and exposes the active set to the
//  chat-loop. Bearer tokens are stored in Keychain via KeychainAccess.
//

import Foundation
import Observation
import KeychainAccess

struct MCPServerConfig: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var endpoint: URL
    var enabled: Bool
    var requiresAuth: Bool

    init(id: UUID = UUID(),
         name: String,
         endpoint: URL,
         enabled: Bool = true,
         requiresAuth: Bool = false) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.enabled = enabled
        self.requiresAuth = requiresAuth
    }
}

@MainActor
@Observable
final class MCPStore {

    private(set) var servers: [MCPServerConfig] = []
    private(set) var connectionStatus: [UUID: ConnectionState] = [:]
    private(set) var lastError: [UUID: String] = [:]

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    let service = MCPClientService()
    private let keychain = Keychain(service: "com.slavkoklincov.lokal.mcp")
        .accessibility(.afterFirstUnlockThisDeviceOnly)

    func bootstrap() {
        load()
    }

    // MARK: - CRUD

    func add(_ config: MCPServerConfig, bearerToken: String?) {
        servers.append(config)
        if let token = bearerToken, !token.isEmpty {
            try? keychain.set(token, key: tokenKey(for: config.id))
        }
        persist()
    }

    func update(_ config: MCPServerConfig, bearerToken: String?) {
        guard let i = servers.firstIndex(where: { $0.id == config.id }) else { return }
        servers[i] = config
        if let token = bearerToken {
            if token.isEmpty {
                try? keychain.remove(tokenKey(for: config.id))
            } else {
                try? keychain.set(token, key: tokenKey(for: config.id))
            }
        }
        persist()
    }

    func remove(_ id: UUID) {
        try? keychain.remove(tokenKey(for: id))
        servers.removeAll { $0.id == id }
        Task { await service.disconnect(serverID: id) }
        connectionStatus[id] = nil
        lastError[id] = nil
        persist()
    }

    func token(for id: UUID) -> String? {
        try? keychain.getString(tokenKey(for: id))
    }

    private func tokenKey(for id: UUID) -> String { "mcp.\(id.uuidString).bearer" }

    // MARK: - Connection lifecycle

    func connect(_ config: MCPServerConfig) async {
        connectionStatus[config.id] = .connecting
        lastError[config.id] = nil
        let bearer = token(for: config.id)
        do {
            try await service.connect(
                serverID: config.id,
                name: config.name,
                endpoint: config.endpoint,
                bearerToken: bearer
            )
            connectionStatus[config.id] = .connected
        } catch {
            connectionStatus[config.id] = .error(error.localizedDescription)
            lastError[config.id] = error.localizedDescription
        }
    }

    func disconnect(_ config: MCPServerConfig) async {
        await service.disconnect(serverID: config.id)
        connectionStatus[config.id] = .disconnected
    }

    func connectAllEnabled() async {
        for s in servers where s.enabled {
            await connect(s)
        }
    }

    func discoveredTools() async -> [MCPClientService.DiscoveredTool] {
        await service.discoveredTools()
    }

    // MARK: - Persistence

    private static func manifestURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("LokaloMCP", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    private struct Manifest: Codable {
        var servers: [MCPServerConfig]
    }

    func persist() {
        do {
            let data = try JSONEncoder().encode(Manifest(servers: servers))
            try data.write(to: Self.manifestURL(), options: [.atomic])
        } catch {
            #if DEBUG
            print("MCPStore persist failed: \(error)")
            #endif
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.manifestURL()) else { return }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return }
        self.servers = manifest.servers
    }
}
