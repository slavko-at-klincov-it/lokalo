//
//  GoogleDriveOAuth.swift
//  Lokal
//
//  PKCE OAuth + Drive v3 REST client. Read-only scope only.
//
//  Set Google OAuth Client ID (iOS type) via UserDefaults key
//  "Lokal.googleDrive.clientID" before using.
//

import Foundation

enum GoogleDriveOAuth {

    static var clientID: String {
        UserDefaults.standard.string(forKey: "Lokal.googleDrive.clientID") ?? ""
    }

    static let scope = "https://www.googleapis.com/auth/drive.readonly"

    /// Reverse-DNS redirect URI required by Google's iOS OAuth client type.
    /// Format: com.googleusercontent.apps.<NUMERIC>:/oauth2redirect
    static var redirectURI: String {
        guard !clientID.isEmpty else { return "" }
        // Strip ".apps.googleusercontent.com" suffix.
        let trimmed = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(trimmed):/oauth2redirect"
    }

    static var callbackScheme: String {
        guard !clientID.isEmpty else { return "" }
        let trimmed = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(trimmed)"
    }

    static func buildAuthorizeURL(pkce: PKCE, state: String) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        return c.url
    }

    struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Int?
        let scope: String?
        let error: String?
        let error_description: String?
    }

    static func exchangeCode(_ code: String, verifier: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let err = resp.error {
            throw OAuthError.tokenExchangeFailed(resp.error_description ?? err)
        }
        guard let access = resp.access_token else { throw OAuthError.noAccessToken }
        let expiresAt = resp.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }
        return OAuthTokens(
            accessToken: access,
            refreshToken: resp.refresh_token,
            expiresAt: expiresAt,
            scope: resp.scope
        )
    }

    static func refresh(token: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "refresh_token": token,
            "grant_type": "refresh_token"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let err = resp.error {
            throw OAuthError.tokenExchangeFailed(resp.error_description ?? err)
        }
        guard let access = resp.access_token else { throw OAuthError.noAccessToken }
        let expiresAt = resp.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }
        return OAuthTokens(
            accessToken: access,
            refreshToken: token, // refresh tokens don't rotate by default
            expiresAt: expiresAt,
            scope: resp.scope
        )
    }

    // MARK: - REST helpers

    struct DriveFile: Decodable, Hashable {
        let id: String
        let name: String
        let mimeType: String
        let size: String?
        let parents: [String]?
    }
    private struct ListResponse: Decodable {
        let files: [DriveFile]
        let nextPageToken: String?
    }

    /// List files in a folder. Pass nil to list root.
    static func listFiles(token: String, parentID: String?) async throws -> [DriveFile] {
        var allFiles: [DriveFile] = []
        var pageToken: String? = nil
        repeat {
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var items: [URLQueryItem] = [
                .init(name: "fields", value: "files(id,name,mimeType,size,parents),nextPageToken"),
                .init(name: "pageSize", value: "100")
            ]
            if let parentID {
                items.append(.init(name: "q", value: "'\(parentID)' in parents and trashed=false"))
            } else {
                items.append(.init(name: "q", value: "'root' in parents and trashed=false"))
            }
            if let pt = pageToken {
                items.append(.init(name: "pageToken", value: pt))
            }
            c.queryItems = items
            var request = URLRequest(url: c.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let resp = try JSONDecoder().decode(ListResponse.self, from: data)
            allFiles.append(contentsOf: resp.files)
            pageToken = resp.nextPageToken
        } while pageToken != nil
        return allFiles
    }

    static func download(token: String, fileID: String, mimeType: String) async throws -> Data {
        // Native Google Docs need /export
        if mimeType.hasPrefix("application/vnd.google-apps.") {
            let exportType = mimeType == "application/vnd.google-apps.spreadsheet" ? "text/csv" : "text/plain"
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/export")!
            c.queryItems = [.init(name: "mimeType", value: exportType)]
            var request = URLRequest(url: c.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } else {
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
            c.queryItems = [.init(name: "alt", value: "media")]
            var request = URLRequest(url: c.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }
    }
}
