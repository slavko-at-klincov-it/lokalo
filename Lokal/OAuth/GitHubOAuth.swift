//
//  GitHubOAuth.swift
//  Lokal
//
//  PKCE OAuth + REST client for GitHub. NOTE: GitHub OAuth Apps still need a
//  client_secret server-side; for native iOS public clients we use the
//  Device Authorization Grant (RFC 8628) which works without a secret.
//
//  Set `clientID` to your GitHub OAuth App's Client ID before using.
//

import Foundation

enum GitHubOAuth {

    /// Replace with your GitHub OAuth App / GitHub App client ID.
    /// Public client — no secret. Use Device Flow (no PKCE for GitHub).
    static var clientID: String {
        UserDefaults.standard.string(forKey: "Lokal.github.clientID") ?? ""
    }

    static let scopes = "public_repo read:user"

    // MARK: - Device Flow (RFC 8628)

    struct DeviceCodeResponse: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let expires_in: Int
        let interval: Int
    }

    struct AccessTokenResponse: Decodable {
        let access_token: String?
        let token_type: String?
        let scope: String?
        let error: String?
        let error_description: String?
    }

    static func startDeviceFlow() async throws -> DeviceCodeResponse {
        guard !clientID.isEmpty else {
            throw OAuthError.providerError("GitHub Client-ID nicht konfiguriert")
        }
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientID)&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes)"
        request.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let resp = try? JSONDecoder().decode(DeviceCodeResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.providerError("Device-Flow fehlgeschlagen: \(body)")
        }
        return resp
    }

    /// Polls GitHub for completion of the user authorization step.
    /// Returns the access token once available, or throws on timeout.
    static func pollForToken(deviceCode: String,
                             interval: Int,
                             expiresIn: Int) async throws -> OAuthTokens {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var pollInterval = max(5, interval)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)
            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let resp = try? JSONDecoder().decode(AccessTokenResponse.self, from: data) else { continue }
            if let token = resp.access_token, !token.isEmpty {
                return OAuthTokens(
                    accessToken: token,
                    refreshToken: nil, // device flow doesn't return one without `repo` scope upgrade
                    expiresAt: nil,
                    scope: resp.scope
                )
            }
            switch resp.error {
            case "authorization_pending":
                continue
            case "slow_down":
                pollInterval += 5
            case "expired_token", "access_denied", "incorrect_device_code":
                throw OAuthError.providerError(resp.error_description ?? resp.error ?? "GitHub Auth abgebrochen")
            default:
                continue
            }
        }
        throw OAuthError.providerError("Device-Code abgelaufen")
    }

    // MARK: - REST API helpers

    struct Repo: Decodable, Hashable {
        let id: Int
        let full_name: String
        let name: String
        let `private`: Bool
        let default_branch: String
    }

    static func listRepos(token: String) async throws -> [Repo] {
        var request = URLRequest(url: URL(string: "https://api.github.com/user/repos?per_page=100&sort=updated")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Lokalo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONDecoder().decode([Repo].self, from: data)) ?? []
    }

    struct TreeNode: Decodable {
        let path: String
        let type: String   // "blob" | "tree"
        let sha: String
        let size: Int?
    }
    private struct TreeResponse: Decodable {
        let tree: [TreeNode]
    }

    static func listTree(token: String,
                         repoFullName: String,
                         branch: String) async throws -> [TreeNode] {
        let url = URL(string: "https://api.github.com/repos/\(repoFullName)/git/trees/\(branch)?recursive=1")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lokalo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONDecoder().decode(TreeResponse.self, from: data))?.tree ?? []
    }

    static func downloadBlob(token: String,
                             repoFullName: String,
                             branch: String,
                             path: String) async throws -> Data {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "https://raw.githubusercontent.com/\(repoFullName)/\(branch)/\(escaped)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Lokalo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
