//
//  OneDriveOAuth.swift
//  Lokal
//
//  Microsoft Graph OAuth + Files.Read REST client. PKCE-based, no client secret.
//  Set Microsoft App Client ID via UserDefaults key "Lokal.oneDrive.clientID".
//

import Foundation

enum OneDriveOAuth {

    static var clientID: String {
        UserDefaults.standard.string(forKey: "Lokal.oneDrive.clientID") ?? ""
    }

    static let scope = "Files.Read offline_access User.Read"

    static let redirectURI = "com.slavkoklincov.lokal://oauth-callback"
    static let callbackScheme = "com.slavkoklincov.lokal"

    static func buildAuthorizeURL(pkce: PKCE, state: String) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var c = URLComponents(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
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
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "scope": scope,
            "code": code,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
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

    static func refresh(refreshToken: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "scope": scope,
            "refresh_token": refreshToken,
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
            refreshToken: resp.refresh_token ?? refreshToken,
            expiresAt: expiresAt,
            scope: resp.scope
        )
    }

    // MARK: - REST helpers

    struct DriveItem: Decodable, Hashable {
        let id: String
        let name: String
        let size: Int?
        let folder: Folder?
        let file: FileMeta?
        struct Folder: Decodable, Hashable { let childCount: Int? }
        struct FileMeta: Decodable, Hashable { let mimeType: String? }
        var isFolder: Bool { folder != nil }
    }

    private struct ChildrenResponse: Decodable {
        let value: [DriveItem]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    static func listChildren(token: String, itemID: String?) async throws -> [DriveItem] {
        let urlString: String
        if let itemID, !itemID.isEmpty, itemID != "root" {
            urlString = "https://graph.microsoft.com/v1.0/me/drive/items/\(itemID)/children?$top=200"
        } else {
            urlString = "https://graph.microsoft.com/v1.0/me/drive/root/children?$top=200"
        }
        var allItems: [DriveItem] = []
        var nextURL: URL? = URL(string: urlString)
        while let url = nextURL {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try JSONDecoder().decode(ChildrenResponse.self, from: data)
            allItems.append(contentsOf: page.value)
            nextURL = page.nextLink.flatMap { URL(string: $0) }
        }
        return allItems
    }

    static func download(token: String, itemID: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(itemID)/content")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
