//
//  MCPClientService.swift
//  Lokal
//
//  Wraps the official `modelcontextprotocol/swift-sdk` Client. Limited to
//  Streamable HTTP transport — stdio is impossible on iOS (no fork/exec).
//

import Foundation
import MCP

actor MCPClientService {

    enum ServiceError: LocalizedError {
        case notConnected
        case toolFailed(String)
        case serverNotConfigured

        var errorDescription: String? {
            switch self {
            case .notConnected:        return "Mit MCP-Server nicht verbunden"
            case .toolFailed(let m):   return "Tool-Aufruf fehlgeschlagen: \(m)"
            case .serverNotConfigured: return "MCP-Server nicht konfiguriert"
            }
        }
    }

    /// Light-weight discovered tool description used by the chat tool loop.
    struct DiscoveredTool: Hashable {
        let serverID: UUID
        let serverName: String
        let toolName: String
        let description: String
        let inputSchema: String?  // JSON schema as text, for the system prompt
    }

    private var clients: [UUID: Client] = [:]
    private var toolsByServer: [UUID: [Tool]] = [:]

    func connect(serverID: UUID,
                 name: String,
                 endpoint: URL,
                 bearerToken: String?) async throws {
        // Disconnect any existing client for this id first.
        await disconnect(serverID: serverID)
        let client = Client(name: "Lokalo", version: "1.0.0")
        let configuration = HTTPClientTransport.Configuration(
            endpoint: endpoint,
            streaming: true
        )
        var transport = HTTPClientTransport(configuration: configuration)
        if let bearerToken {
            transport.urlSession.configuration.httpAdditionalHeaders = [
                "Authorization": "Bearer \(bearerToken)"
            ]
        }
        try await client.connect(transport: transport)
        clients[serverID] = client
        do {
            let (tools, _) = try await client.listTools()
            toolsByServer[serverID] = tools
        } catch {
            toolsByServer[serverID] = []
        }
    }

    func disconnect(serverID: UUID) async {
        if let client = clients[serverID] {
            try? await client.disconnect()
        }
        clients.removeValue(forKey: serverID)
        toolsByServer.removeValue(forKey: serverID)
    }

    func disconnectAll() async {
        for id in Array(clients.keys) {
            await disconnect(serverID: id)
        }
    }

    func discoveredTools() -> [DiscoveredTool] {
        var out: [DiscoveredTool] = []
        for (serverID, tools) in toolsByServer {
            for t in tools {
                out.append(DiscoveredTool(
                    serverID: serverID,
                    serverName: "MCP",
                    toolName: t.name,
                    description: t.description ?? "(no description)",
                    inputSchema: nil
                ))
            }
        }
        return out
    }

    func callTool(serverID: UUID,
                  name: String,
                  arguments: [String: Value]) async throws -> String {
        guard let client = clients[serverID] else {
            throw ServiceError.notConnected
        }
        let (content, isError) = try await client.callTool(name: name, arguments: arguments)
        let textPieces: [String] = content.compactMap { piece in
            if case .text(let t) = piece { return t }
            return nil
        }
        let combined = textPieces.joined(separator: "\n")
        if isError == true {
            throw ServiceError.toolFailed(combined.isEmpty ? "Unknown error" : combined)
        }
        return combined.isEmpty ? "(tool returned no content)" : combined
    }
}

// MARK: - Conversion: AnyCodable -> MCP.Value

extension MCPClientService {
    nonisolated static func convert(arguments: [String: AnyCodable]) -> [String: Value] {
        var out: [String: Value] = [:]
        for (k, v) in arguments {
            out[k] = convertValue(v.value)
        }
        return out
    }

    private nonisolated static func convertValue(_ any: Any) -> Value {
        switch any {
        case let s as String:  return .string(s)
        case let i as Int:     return .int(i)
        case let d as Double:  return .double(d)
        case let b as Bool:    return .bool(b)
        case is NSNull:        return .null
        case let arr as [Any]: return .array(arr.map { convertValue($0) })
        case let dict as [String: Any]:
            var obj: [String: Value] = [:]
            for (k, v) in dict { obj[k] = convertValue(v) }
            return .object(obj)
        default:
            return .string(String(describing: any))
        }
    }
}
