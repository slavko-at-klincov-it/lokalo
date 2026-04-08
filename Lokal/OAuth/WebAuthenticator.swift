//
//  WebAuthenticator.swift
//  Lokal
//
//  Async wrapper around ASWebAuthenticationSession.
//

import Foundation
import AuthenticationServices
import UIKit

@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { callback, error in
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.authCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let callback {
                    continuation.resume(returning: callback)
                    return
                }
                continuation.resume(throwing: OAuthError.missingCode)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
