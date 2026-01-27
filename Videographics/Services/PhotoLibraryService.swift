//
//  PhotoLibraryService.swift
//  Videographics
//

import Foundation
import Photos
import PhotosUI
import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

struct ImportedMediaInfo {
    let url: URL
    let duration: CMTime
    let naturalSize: CGSize
    let hasAudio: Bool
}

@MainActor
class PhotoLibraryService: ObservableObject {
    static let shared = PhotoLibraryService()

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    init() {
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    /// Process a PhotosPicker selection and copy to project storage
    func processPickerItem(
        _ item: PhotosPickerItem,
        projectId: UUID
    ) async throws -> ImportedMediaInfo {
        // Load the video as transferable
        guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
            throw PhotoLibraryError.failedToLoadVideo
        }

        // Copy to project storage
        let destinationURL = try await FileStorageService.shared.copyMediaToProject(
            sourceURL: movie.url,
            projectId: projectId
        )

        // Get video info
        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration)

        var naturalSize = CGSize(width: 1080, height: 1920)
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            // Apply transform to get actual dimensions
            let transformedSize = naturalSize.applying(transform)
            naturalSize = CGSize(
                width: abs(transformedSize.width),
                height: abs(transformedSize.height)
            )
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let hasAudio = !audioTracks.isEmpty

        // Clean up the temporary file
        try? FileManager.default.removeItem(at: movie.url)

        return ImportedMediaInfo(
            url: destinationURL,
            duration: duration,
            naturalSize: naturalSize,
            hasAudio: hasAudio
        )
    }

    /// Save video to Photo Library
    func saveToPhotoLibrary(url: URL) async throws {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.notAuthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)

            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

// MARK: - Errors

enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case failedToLoadVideo
    case failedToSave

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo Library access not authorized"
        case .failedToLoadVideo:
            return "Failed to load video from Photo Library"
        case .failedToSave:
            return "Failed to save video to Photo Library"
        }
    }
}
