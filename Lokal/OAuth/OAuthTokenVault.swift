//
//  OAuthTokenVault.swift
//  Lokal
//
//  Keychain-backed token storage for OAuth providers. Uses
//  `.afterFirstUnlockThisDeviceOnly` so refresh works in background tasks
//  but the tokens never sync to iCloud Keychain.
//

import Foundation
import KeychainAccess

enum OAuthProvider: String, Codable, Hashable, CaseIterable {
    case github
    case googleDrive
    case onedrive

    var displayName: String {
        switch self {
        case .github:      return "GitHub"
        case .googleDrive: return "Google Drive"
        case .onedrive:    return "OneDrive"
        }
    }

    var iconName: String {
        switch self {
        case .github:      return "chevron.left.forwardslash.chevron.right"
        case .googleDrive: return "doc.circle"
        case .onedrive:    return "cloud"
        }
    }
}

struct OAuthTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scope: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Consider expired 30s before the actual deadline.
        return Date().addingTimeInterval(30) >= expiresAt
    }
}

final class OAuthTokenVault {

    static let shared = OAuthTokenVault()

    private let keychain: Keychain

    private init() {
        self.keychain = Keychain(service: "com.slavkoklincov.lokal.oauth")
            .accessibility(.afterFirstUnlockThisDeviceOnly)
    }

    func store(_ tokens: OAuthTokens, for provider: OAuthProvider) {
        do {
            let data = try JSONEncoder().encode(tokens)
            try keychain.set(data, key: provider.rawValue)
        } catch {
            #if DEBUG
            print("OAuthTokenVault store error: \(error)")
            #endif
        }
    }

    func tokens(for provider: OAuthProvider) -> OAuthTokens? {
        guard let data = try? keychain.getData(provider.rawValue) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func clear(_ provider: OAuthProvider) {
        try? keychain.remove(provider.rawValue)
    }
}
