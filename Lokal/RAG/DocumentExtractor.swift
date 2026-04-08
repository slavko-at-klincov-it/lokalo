//
//  DocumentExtractor.swift
//  Lokal
//
//  Extracts plain text out of supported file types so they can be chunked
//  and embedded.
//
//  Supported v1: txt/md/source-code, PDF, RTF, HTML.
//  DOCX/XLSX is intentionally not supported (no first-class iOS API).
//

import Foundation
import PDFKit
import UniformTypeIdentifiers

struct ExtractedPage: Hashable {
    let pageIndex: Int?
    let text: String
}

struct ExtractedDocument: Hashable {
    let sourceURL: URL
    let displayName: String
    let pages: [ExtractedPage]

    var isEmpty: Bool { pages.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

enum DocumentExtractorError: LocalizedError {
    case unsupported(String)
    case readFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unsupported(let kind): return "Unsupported file type: \(kind)"
        case .readFailed(let e):     return "Could not read document: \(e.localizedDescription)"
        }
    }
}

enum DocumentExtractor {

    static let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "tex", "log",
        "swift", "h", "m", "mm", "c", "cpp", "cc", "hpp",
        "py", "rb", "rs", "go", "java", "kt", "kts", "scala",
        "js", "jsx", "ts", "tsx", "vue", "svelte",
        "html", "htm", "xml", "json", "yml", "yaml", "toml", "csv", "tsv",
        "css", "scss", "less", "sql",
        "pdf", "rtf"
    ]

    static func canExtract(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func extract(from url: URL) throws -> ExtractedDocument {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return try extractPDF(url: url)
        case "html", "htm":
            return try extractHTML(url: url)
        case "rtf":
            return try extractRTF(url: url)
        default:
            return try extractPlainText(url: url)
        }
    }

    private static func extractPDF(url: URL) throws -> ExtractedDocument {
        guard let doc = PDFDocument(url: url) else {
            throw DocumentExtractorError.readFailed(CocoaError(.fileReadCorruptFile))
        }
        var pages: [ExtractedPage] = []
        for i in 0..<doc.pageCount {
            let pageText = doc.page(at: i)?.string ?? ""
            pages.append(ExtractedPage(pageIndex: i, text: pageText))
        }
        return ExtractedDocument(sourceURL: url, displayName: url.lastPathComponent, pages: pages)
    }

    private static func extractPlainText(url: URL) throws -> ExtractedDocument {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return ExtractedDocument(
                sourceURL: url,
                displayName: url.lastPathComponent,
                pages: [ExtractedPage(pageIndex: nil, text: text)]
            )
        } catch {
            // Try Latin-1 fallback for legacy files.
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .isoLatin1) ?? ""
            return ExtractedDocument(
                sourceURL: url,
                displayName: url.lastPathComponent,
                pages: [ExtractedPage(pageIndex: nil, text: text)]
            )
        }
    }

    private static func extractRTF(url: URL) throws -> ExtractedDocument {
        let data = try Data(contentsOf: url)
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        let attr = try NSAttributedString(data: data, options: opts, documentAttributes: nil)
        return ExtractedDocument(
            sourceURL: url,
            displayName: url.lastPathComponent,
            pages: [ExtractedPage(pageIndex: nil, text: attr.string)]
        )
    }

    private static func extractHTML(url: URL) throws -> ExtractedDocument {
        // NSAttributedString HTML loading must run on the main thread on iOS.
        // Indexer dispatches off-main, so we strip tags via a fast regex
        // fallback here instead. Quality < NSAttributedString but safe.
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stripped = stripHTML(raw)
        return ExtractedDocument(
            sourceURL: url,
            displayName: url.lastPathComponent,
            pages: [ExtractedPage(pageIndex: nil, text: stripped)]
        )
    }

    private static func stripHTML(_ s: String) -> String {
        // Drop scripts/styles, then tags, then collapse whitespace, then
        // decode the most common HTML entities.
        var t = s
        t = t.replacingOccurrences(
            of: "<script[^>]*?>[\\s\\S]*?</script>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        t = t.replacingOccurrences(
            of: "<style[^>]*?>[\\s\\S]*?</style>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "&amp;",  with: "&")
        t = t.replacingOccurrences(of: "&lt;",   with: "<")
        t = t.replacingOccurrences(of: "&gt;",   with: ">")
        t = t.replacingOccurrences(of: "&quot;", with: "\"")
        t = t.replacingOccurrences(of: "&#39;",  with: "'")
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
