//
//  ExportService.swift
//  Videographics
//

import Foundation
import AVFoundation
import CoreMedia
import Combine

/// Export state for tracking progress
enum ExportState: Equatable {
    case idle
    case preparing
    case exporting(progress: Float)
    case saving
    case completed(url: URL)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .preparing, .exporting, .saving:
            return true
        default:
            return false
        }
    }
}

/// Export error types
enum ExportError: LocalizedError {
    case noTimeline
    case compositionFailed
    case exportSessionCreationFailed
    case exportFailed(String)
    case cancelled
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .noTimeline:
            return "No timeline to export"
        case .compositionFailed:
            return "Failed to build composition"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .cancelled:
            return "Export was cancelled"
        case .fileWriteFailed:
            return "Failed to write export file"
        }
    }
}

/// Service for exporting video compositions
@MainActor
class ExportService: ObservableObject {
    static let shared = ExportService()

    @Published var exportState: ExportState = .idle

    private var currentExportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?

    /// Export a timeline with the given preset
    func export(
        timeline: Timeline,
        preset: ExportPreset,
        projectId: UUID
    ) async throws -> URL {
        exportState = .preparing

        // Build composition
        guard let result = await CompositionEngine.shared.buildComposition(
            from: timeline,
            renderSize: preset.resolution
        ) else {
            exportState = .failed(message: "Failed to build composition")
            throw ExportError.compositionFailed
        }

        // Create export URL
        let exportsDir = await FileStorageService.shared.projectDirectory(for: projectId)
            .appendingPathComponent("Exports", isDirectory: true)

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: exportsDir.path) {
            try? fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let exportURL = exportsDir.appendingPathComponent("export_\(timestamp).mp4")

        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: result.composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            exportState = .failed(message: "Failed to create export session")
            throw ExportError.exportSessionCreationFailed
        }

        currentExportSession = exportSession

        // Configure export session
        exportSession.outputURL = exportURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Log composition details for debugging
        print("=== Export Debug Info ===")
        print("Composition duration: \(result.composition.duration.seconds)s")
        do {
            let videoTracks = try await result.composition.loadTracks(withMediaType: .video)
            let audioTracks = try await result.composition.loadTracks(withMediaType: .audio)
            print("Video tracks: \(videoTracks.count)")
            print("Audio tracks: \(audioTracks.count)")
            for (i, track) in videoTracks.enumerated() {
                let timeRange = try await track.load(.timeRange)
                print("Video track \(i): duration=\(timeRange.duration.seconds)s")
            }
        } catch {
            print("Could not load track info: \(error)")
        }
        print("=========================")

        // Don't use video composition for now - export raw composition
        // This helps debug if the issue is with video composition or the source files

        // Start progress monitoring
        startProgressMonitoring(session: exportSession)

        // Perform export
        await exportSession.export()

        // Stop progress monitoring
        stopProgressMonitoring()

        // Check result
        switch exportSession.status {
        case .completed:
            exportState = .completed(url: exportURL)
            currentExportSession = nil
            return exportURL

        case .failed:
            let error = exportSession.error
            let errorMessage = error?.localizedDescription ?? "Unknown error"

            // Log detailed error info
            if let error = error as NSError? {
                print("Export failed with error: \(error)")
                print("Error domain: \(error.domain)")
                print("Error code: \(error.code)")
                print("Error userInfo: \(error.userInfo)")
            }

            exportState = .failed(message: errorMessage)
            currentExportSession = nil
            throw ExportError.exportFailed(errorMessage)

        case .cancelled:
            exportState = .failed(message: "Export cancelled")
            currentExportSession = nil
            throw ExportError.cancelled

        default:
            exportState = .failed(message: "Unexpected export status")
            currentExportSession = nil
            throw ExportError.exportFailed("Unexpected export status")
        }
    }

    /// Cancel the current export
    func cancelExport() {
        currentExportSession?.cancelExport()
        currentExportSession = nil
        stopProgressMonitoring()
        exportState = .idle
    }

    /// Reset export state
    func reset() {
        exportState = .idle
        currentExportSession = nil
        stopProgressMonitoring()
    }

    private func startProgressMonitoring(session: AVAssetExportSession) {
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                let progress = session.progress
                if case .exporting = exportState {
                    exportState = .exporting(progress: progress)
                } else if exportState == .preparing {
                    exportState = .exporting(progress: progress)
                }

                if progress >= 1.0 || session.status != .exporting {
                    break
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopProgressMonitoring() {
        progressTask?.cancel()
        progressTask = nil
    }
}

// MARK: - Export Validation

extension ExportService {
    /// Validate timeline duration against preset limits
    static func validateDuration(timeline: Timeline, preset: ExportPreset) -> (valid: Bool, message: String?) {
        guard let maxDuration = preset.platform.maxDuration else {
            return (true, nil)
        }

        let timelineDuration = timeline.duration
        if timelineDuration > maxDuration {
            let maxSeconds = Int(maxDuration.seconds)
            let currentSeconds = Int(timelineDuration.seconds)
            return (false, "Video is \(currentSeconds)s but \(preset.platform.rawValue) max is \(maxSeconds)s")
        }

        return (true, nil)
    }
}
