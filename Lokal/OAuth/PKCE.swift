//
//  PKCE.swift
//  Lokal
//
//  RFC 7636 PKCE helper. Generates a high-entropy verifier and the
//  S256 challenge derived from it via SHA-256.
//

import Foundation
import CryptoKit

struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncodedString()
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: LocalizedError {
    case authCancelled
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case noAccessToken
    case noRefreshToken
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .authCancelled:               return "Anmeldung abgebrochen"
        case .missingCode:                 return "Kein Auth-Code erhalten"
        case .stateMismatch:               return "OAuth state mismatch"
        case .tokenExchangeFailed(let m):  return "Token-Tausch fehlgeschlagen: \(m)"
        case .noAccessToken:               return "Kein Access-Token erhalten"
        case .noRefreshToken:              return "Kein Refresh-Token verfügbar"
        case .providerError(let m):        return m
        }
    }
}
