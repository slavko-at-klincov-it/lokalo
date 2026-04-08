//
//  ConnectionStore.swift
//  Lokal
//
//  @Observable façade over the OAuth providers. Holds the connection state
//  per provider, performs login flows, and serves as the file fetcher used
//  by IndexingService for remote sources.
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectionStore {

    struct Connection: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        var provider: OAuthProvider
        var displayName: String  // username/email
        var connectedAt: Date

        init(id: UUID = UUID(), provider: OAuthProvider, displayName: String) {
            self.id = id
            self.provider = provider
            self.displayName = displayName
            self.connectedAt = .now
        }
    }

    private(set) var connections: [Connection] = []
    var lastError: String?

    private let vault = OAuthTokenVault.shared
    private let webAuth = WebAuthenticator()

    func bootstrap() {
        load()
    }

    func connection(for provider: OAuthProvider) -> Connection? {
        connections.first { $0.provider == provider }
    }

    func isConnected(_ provider: OAuthProvider) -> Bool {
        connection(for: provider) != nil && vault.tokens(for: provider) != nil
    }

    // MARK: - Sign-in flows

    func signIn(_ provider: OAuthProvider) async {
        do {
            switch provider {
            case .github:
                try await signInGitHub()
            case .googleDrive:
                try await signInGoogleDrive()
            case .onedrive:
                try await signInOneDrive()
            }
        } catch {
            lastError = error.lokaloMessage
        }
    }

    func signOut(_ provider: OAuthProvider) {
        vault.clear(provider)
        connections.removeAll { $0.provider == provider }
        persist()
    }

    private func signInGitHub() async throws {
        let device = try await GitHubOAuth.startDeviceFlow()
        // The user code + verification URL must be displayed by the UI.
        await MainActor.run {
            self.pendingDeviceFlow = .init(
                userCode: device.user_code,
                verificationURL: device.verification_uri,
                expiresAt: Date().addingTimeInterval(TimeInterval(device.expires_in))
            )
        }
        defer {
            Task { @MainActor in self.pendingDeviceFlow = nil }
        }
        let tokens = try await GitHubOAuth.pollForToken(
            deviceCode: device.device_code,
            interval: device.interval,
            expiresIn: device.expires_in
        )
        vault.store(tokens, for: .github)
        let username = (try? await fetchGitHubUsername(token: tokens.accessToken)) ?? "GitHub"
        let conn = Connection(provider: .github, displayName: username)
        connections.removeAll { $0.provider == .github }
        connections.append(conn)
        persist()
    }

    private func fetchGitHubUsername(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lokalo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct U: Decodable { let login: String }
        return (try? JSONDecoder().decode(U.self, from: data))?.login ?? "GitHub"
    }

    private func signInGoogleDrive() async throws {
        guard !GoogleDriveOAuth.clientID.isEmpty else {
            throw OAuthError.providerError("Google Drive Client-ID nicht konfiguriert")
        }
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        guard let url = GoogleDriveOAuth.buildAuthorizeURL(pkce: pkce, state: state) else {
            throw OAuthError.providerError("Konnte Authorize-URL nicht bauen")
        }
        let callback = try await webAuth.authenticate(
            url: url,
            callbackURLScheme: GoogleDriveOAuth.callbackScheme
        )
        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        if let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value,
           returnedState != state {
            throw OAuthError.stateMismatch
        }
        let tokens = try await GoogleDriveOAuth.exchangeCode(code, verifier: pkce.verifier)
        vault.store(tokens, for: .googleDrive)
        let conn = Connection(provider: .googleDrive, displayName: "Google Drive")
        connections.removeAll { $0.provider == .googleDrive }
        connections.append(conn)
        persist()
    }

    private func signInOneDrive() async throws {
        guard !OneDriveOAuth.clientID.isEmpty else {
            throw OAuthError.providerError("OneDrive Client-ID nicht konfiguriert")
        }
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        guard let url = OneDriveOAuth.buildAuthorizeURL(pkce: pkce, state: state) else {
            throw OAuthError.providerError("Konnte Authorize-URL nicht bauen")
        }
        let callback = try await webAuth.authenticate(
            url: url,
            callbackURLScheme: OneDriveOAuth.callbackScheme
        )
        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        if let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value,
           returnedState != state {
            throw OAuthError.stateMismatch
        }
        let tokens = try await OneDriveOAuth.exchangeCode(code, verifier: pkce.verifier)
        vault.store(tokens, for: .onedrive)
        let conn = Connection(provider: .onedrive, displayName: "OneDrive")
        connections.removeAll { $0.provider == .onedrive }
        connections.append(conn)
        persist()
    }

    // MARK: - Device-flow display state

    struct DeviceFlowState: Hashable {
        let userCode: String
        let verificationURL: String
        let expiresAt: Date
    }
    var pendingDeviceFlow: DeviceFlowState?

    // MARK: - Token freshness

    func freshAccessToken(for provider: OAuthProvider) async throws -> String {
        guard var tokens = vault.tokens(for: provider) else {
            throw OAuthError.noAccessToken
        }
        if tokens.isExpired, let refresh = tokens.refreshToken {
            switch provider {
            case .googleDrive:
                tokens = try await GoogleDriveOAuth.refresh(token: refresh)
            case .onedrive:
                tokens = try await OneDriveOAuth.refresh(refreshToken: refresh)
            case .github:
                break // GitHub device flow tokens currently don't refresh
            }
            vault.store(tokens, for: provider)
        }
        return tokens.accessToken
    }

    // MARK: - File fetching for IndexingService

    /// Walks the remote root identified by `source` and writes every supported
    /// file into `destination`. Used by `IndexingService` to materialize remote
    /// sources before chunking/embedding.
    func fetchAllFiles(for source: KnowledgeSource, into destination: URL) async throws {
        switch source.kind {
        case .githubRepo:
            try await fetchGitHubFiles(source: source, destination: destination)
        case .googleDriveFolder:
            try await fetchGoogleDriveFiles(source: source, destination: destination)
        case .onedriveFolder:
            try await fetchOneDriveFiles(source: source, destination: destination)
        case .localFolder:
            return
        }
    }

    private func fetchGitHubFiles(source: KnowledgeSource, destination: URL) async throws {
        guard let repoFullName = source.remoteRootID else { return }
        let token = try await freshAccessToken(for: .github)
        // Default branch lookup
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repoFullName)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lokalo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct R: Decodable { let default_branch: String }
        let branch = (try? JSONDecoder().decode(R.self, from: data))?.default_branch ?? "main"

        let tree = try await GitHubOAuth.listTree(token: token, repoFullName: repoFullName, branch: branch)
        for node in tree where node.type == "blob" {
            if let size = node.size, size > 1_000_000 { continue } // skip > 1 MB
            let url = URL(fileURLWithPath: node.path)
            guard DocumentExtractor.canExtract(url: url) else { continue }
            do {
                let bytes = try await GitHubOAuth.downloadBlob(
                    token: token,
                    repoFullName: repoFullName,
                    branch: branch,
                    path: node.path
                )
                let local = destination.appendingPathComponent(node.path)
                try FileManager.default.createDirectory(
                    at: local.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try bytes.write(to: local)
            } catch {
                continue
            }
        }
    }

    private func fetchGoogleDriveFiles(source: KnowledgeSource, destination: URL) async throws {
        let token = try await freshAccessToken(for: .googleDrive)
        try await walkGoogleDrive(parentID: source.remoteRootID, token: token, destination: destination)
    }

    private func walkGoogleDrive(parentID: String?, token: String, destination: URL) async throws {
        let files = try await GoogleDriveOAuth.listFiles(token: token, parentID: parentID)
        for f in files {
            if f.mimeType == "application/vnd.google-apps.folder" {
                try await walkGoogleDrive(parentID: f.id, token: token, destination: destination)
            } else {
                if let sizeStr = f.size, let size = Int(sizeStr), size > 5_000_000 { continue }
                // For native Google Docs we end up with .txt; for binary files use original extension.
                let suffix = f.mimeType.hasPrefix("application/vnd.google-apps.") ? ".txt" : ""
                let fileName = f.name + suffix
                let url = URL(fileURLWithPath: fileName)
                if DocumentExtractor.canExtract(url: url) || f.mimeType.hasPrefix("application/vnd.google-apps.") {
                    do {
                        let data = try await GoogleDriveOAuth.download(
                            token: token,
                            fileID: f.id,
                            mimeType: f.mimeType
                        )
                        let local = destination.appendingPathComponent(fileName)
                        try data.write(to: local)
                    } catch {
                        continue
                    }
                }
            }
        }
    }

    private func fetchOneDriveFiles(source: KnowledgeSource, destination: URL) async throws {
        let token = try await freshAccessToken(for: .onedrive)
        try await walkOneDrive(itemID: source.remoteRootID, token: token, destination: destination)
    }

    private func walkOneDrive(itemID: String?, token: String, destination: URL) async throws {
        let children = try await OneDriveOAuth.listChildren(token: token, itemID: itemID)
        for item in children {
            if item.isFolder {
                try await walkOneDrive(itemID: item.id, token: token, destination: destination)
            } else {
                if let size = item.size, size > 5_000_000 { continue }
                let url = URL(fileURLWithPath: item.name)
                guard DocumentExtractor.canExtract(url: url) else { continue }
                do {
                    let data = try await OneDriveOAuth.download(token: token, itemID: item.id)
                    let local = destination.appendingPathComponent(item.name)
                    try data.write(to: local)
                } catch {
                    continue
                }
            }
        }
    }

    // MARK: - Persistence

    private static func manifestURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("LokaloConnections", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connections.json")
    }

    private struct Manifest: Codable { var connections: [Connection] }

    func persist() {
        do {
            let data = try JSONEncoder().encode(Manifest(connections: connections))
            try data.write(to: Self.manifestURL(), options: [.atomic])
        } catch {
            #if DEBUG
            print("ConnectionStore persist failed: \(error)")
            #endif
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.manifestURL()) else { return }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return }
        self.connections = manifest.connections
    }
}
