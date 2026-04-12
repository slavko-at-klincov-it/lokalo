//
//  LokaloError.swift
//  Lokal
//
//  Single source of truth for user-facing error messages. Two layers:
//
//  1. `LokaloError` — a typed enum the app can throw deliberately when it
//     wants a specific German message in the UI.
//  2. `Error.lokaloMessage` — a wrapper that turns ANY thrown error
//     (URLError, CocoaError, llama.cpp wrapper errors, MCP / OAuth errors,
//     anonymous NSError) into a German user-facing string. Replaces every
//     `error.localizedDescription` site so that German UI never gets
//     decorated with English Apple error text.
//
//  Use:
//
//      catch {
//          self.errorMessage = error.lokaloMessage
//      }
//
//  Add new domain-specific cases as the app grows.
//

import Foundation

enum LokaloError: LocalizedError {
    case storage(String)
    case network(String)
    case modelLoad(String)
    case download(String)
    case rag(String)
    case mcp(String)
    case oauth(String)
    case speech(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .storage(let m):   return "Speicher: \(m)"
        case .network(let m):   return "Netzwerk: \(m)"
        case .modelLoad(let m): return "Modell konnte nicht geladen werden: \(m)"
        case .download(let m):  return "Download fehlgeschlagen: \(m)"
        case .rag(let m):       return "Wissensbasis: \(m)"
        case .mcp(let m):       return "MCP-Server: \(m)"
        case .oauth(let m):     return "Anmeldung fehlgeschlagen: \(m)"
        case .speech(let m):    return "Spracheingabe: \(m)"
        case .unknown(let m):   return m
        }
    }
}

extension Error {
    /// German user-facing message for any thrown error. Maps the most common
    /// Apple frameworks to German strings; falls back to a sanitized
    /// representation for unknown error types so the UI never shows raw
    /// English `localizedDescription` text from `NSURLErrorDomain` etc.
    var lokaloMessage: String {
        if let l = self as? LokaloError {
            return l.errorDescription ?? "Unbekannter Fehler."
        }
        if let llama = self as? LlamaError {
            return Self.germanForLlama(llama)
        }
        let nsError = self as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return Self.germanForURLError(code: nsError.code)
        case NSCocoaErrorDomain:
            return Self.germanForCocoaError(code: nsError.code, fallback: nsError.localizedDescription)
        case NSPOSIXErrorDomain:
            return "Systemfehler (Code \(nsError.code))."
        default:
            // For unknown domains we still don't trust localizedDescription
            // (often English). Show a short German wrapper that includes the
            // domain so a developer can find it in logs without exposing
            // half-English UI to the user.
            return "Unbekannter Fehler (\(nsError.domain))."
        }
    }

    private static func germanForLlama(_ err: LlamaError) -> String {
        switch err {
        case .modelLoadFailed(let path):
            return "Modell konnte nicht geladen werden: \(path)"
        case .contextInitFailed:
            return "Modell-Kontext konnte nicht initialisiert werden."
        case .decodeFailed(let r):
            return "Inferenz fehlgeschlagen (Code \(r))."
        case .tokenizationFailed:
            return "Eingabe konnte nicht in Tokens zerlegt werden."
        case .alreadyGenerating:
            return "Modell ist bereits am Antworten."
        case .contextTooSmall(let n, let m):
            return "Kontext (\(n) Tokens) ist zu klein für \(m) gewünschte Antwort-Tokens."
        }
    }

    private static func germanForURLError(code: Int) -> String {
        // The most user-relevant URLError codes — others fall through to a
        // generic message. Apple's localizedDescription for these is in
        // English on a German-locale device, which is exactly the bug.
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "Keine Internetverbindung."
        case NSURLErrorTimedOut:
            return "Verbindung abgelaufen."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return "Server nicht erreichbar."
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
            return "Adresse ungültig."
        case NSURLErrorCancelled:
            return "Vorgang abgebrochen."
        case NSURLErrorUserCancelledAuthentication, NSURLErrorUserAuthenticationRequired:
            return "Anmeldung erforderlich oder abgebrochen."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "Sichere Verbindung fehlgeschlagen."
        case NSURLErrorCannotDecodeContentData, NSURLErrorCannotParseResponse:
            return "Server-Antwort konnte nicht verarbeitet werden."
        case NSURLErrorDataLengthExceedsMaximum:
            return "Antwort zu groß."
        default:
            return "Netzwerkfehler (Code \(code))."
        }
    }

    private static func germanForCocoaError(code: Int, fallback: String) -> String {
        switch code {
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
            return "Datei nicht gefunden."
        case NSFileWriteOutOfSpaceError:
            return "Kein Speicher mehr frei."
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return "Keine Berechtigung für die Datei."
        case NSFileReadCorruptFileError:
            return "Datei ist beschädigt."
        default:
            // We deliberately don't return the English fallback. Show a
            // short German message with the code for triage instead.
            _ = fallback
            return "Dateifehler (Code \(code))."
        }
    }
}
