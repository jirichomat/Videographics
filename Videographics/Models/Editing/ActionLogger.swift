//
//  ActionLogger.swift
//  Videographics
//

import Foundation
import OSLog

/// Debug logger for tracking edit actions and UI events
@MainActor
class ActionLogger {
    static let shared = ActionLogger()

    private let logger = Logger(subsystem: "com.videographics", category: "EditActions")
    private var logEntries: [LogEntry] = []
    private let maxEntries = 500
    private let logFileURL: URL?

    struct LogEntry: Codable {
        let timestamp: Date
        let type: LogType
        let action: String
        let details: String?

        enum LogType: String, Codable {
            case perform
            case undo
            case redo
            case uiEvent
            case error
        }
    }

    private init() {
        // Create log file in Documents directory for easy access
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            logFileURL = documentsPath.appendingPathComponent("videographics_actions.log")
            // Clear old log on app start
            try? FileManager.default.removeItem(at: logFileURL!)
        } else {
            logFileURL = nil
        }
    }

    // MARK: - Logging Methods

    /// Log an action being performed
    func logPerform(_ action: EditAction, details: String? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            type: .perform,
            action: action.actionDescription,
            details: details
        )
        addEntry(entry)
        logger.info("PERFORM: \(action.actionDescription)\(details.map { " - \($0)" } ?? "")")
    }

    /// Log an action being undone
    func logUndo(_ action: EditAction, details: String? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            type: .undo,
            action: action.actionDescription,
            details: details
        )
        addEntry(entry)
        logger.info("UNDO: \(action.actionDescription)\(details.map { " - \($0)" } ?? "")")
    }

    /// Log an action being redone
    func logRedo(_ action: EditAction, details: String? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            type: .redo,
            action: action.actionDescription,
            details: details
        )
        addEntry(entry)
        logger.info("REDO: \(action.actionDescription)\(details.map { " - \($0)" } ?? "")")
    }

    /// Log a UI event (tool change, selection, etc.)
    func logUIEvent(_ event: String, details: String? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            type: .uiEvent,
            action: event,
            details: details
        )
        addEntry(entry)
        logger.debug("UI: \(event)\(details.map { " - \($0)" } ?? "")")
    }

    /// Log an error
    func logError(_ error: String, details: String? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            type: .error,
            action: error,
            details: details
        )
        addEntry(entry)
        logger.error("ERROR: \(error)\(details.map { " - \($0)" } ?? "")")
    }

    // MARK: - Private Methods

    private func addEntry(_ entry: LogEntry) {
        logEntries.append(entry)

        // Trim if over limit
        if logEntries.count > maxEntries {
            logEntries.removeFirst(logEntries.count - maxEntries)
        }

        // Write to file
        appendToFile(entry)
    }

    private func appendToFile(_ entry: LogEntry) {
        guard let url = logFileURL else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let line = "[\(formatter.string(from: entry.timestamp))] [\(entry.type.rawValue.uppercased())] \(entry.action)\(entry.details.map { " | \($0)" } ?? "")\n"

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Debug Access

    /// Get recent log entries for debugging
    func getRecentEntries(count: Int = 50) -> [LogEntry] {
        Array(logEntries.suffix(count))
    }

    /// Get formatted log string for display
    func getFormattedLog(count: Int = 50) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return getRecentEntries(count: count).map { entry in
            let time = formatter.string(from: entry.timestamp)
            let type = entry.type.rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)
            let details = entry.details.map { " | \($0)" } ?? ""
            return "[\(time)] [\(type)] \(entry.action)\(details)"
        }.joined(separator: "\n")
    }

    /// Get log file path for sharing
    var logFilePath: URL? {
        logFileURL
    }

    /// Clear all logs
    func clear() {
        logEntries.removeAll()
        if let url = logFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
