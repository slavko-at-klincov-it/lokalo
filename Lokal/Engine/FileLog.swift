//
//  FileLog.swift
//  Lokalo
//
//  Append-only file logger that writes to Documents/lokalo.log on the device.
//  Pull via:
//    xcrun devicectl device copy from \
//      --device <UDID> --user mobile \
//      --domain-type appDataContainer \
//      --domain-identifier com.slavkoklincov.lokal \
//      --source Documents/lokalo.log \
//      --destination /tmp/
//

import Foundation
import os

enum FileLog {
    private static let queue = DispatchQueue(label: "lokalo.filelog", qos: .utility)
    private static let logger = Logger(subsystem: "com.slavkoklincov.lokal", category: "app")

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static var logFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("lokalo.log")
    }

    /// Truncate the log file at app launch so each session starts fresh.
    static func resetForLaunch() {
        queue.async {
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
            write("=== Lokalo session start \(formatter.string(from: Date())) ===")
        }
    }

    /// Write a message to the log file (and to os.Logger so Console.app can see it too).
    static func write(_ message: String, file: String = #fileID, line: Int = #line) {
        let stamp = formatter.string(from: Date())
        let location = file.split(separator: "/").last.map(String.init) ?? file
        let line = "\(stamp) [\(location):\(line)] \(message)\n"
        logger.log("\(message, privacy: .public)")
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    // File doesn't exist yet — create it.
                    try? data.write(to: logFileURL)
                }
            }
        }
    }
}
