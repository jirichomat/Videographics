//
//  URLVideoDownloader.swift
//  Videographics
//

import Foundation
import AVFoundation
import CoreMedia

actor URLVideoDownloader {
    static let shared = URLVideoDownloader()

    enum DownloadError: LocalizedError {
        case invalidURL
        case downloadFailed(Error)
        case noData
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .downloadFailed(let error):
                return "Download failed: \(error.localizedDescription)"
            case .noData:
                return "No data received"
            case .saveFailed:
                return "Failed to save video"
            }
        }
    }

    /// Download video from URL and save to project storage
    func downloadVideo(from urlString: String, projectId: UUID, onProgress: @escaping (Double) -> Void) async throws -> ImportedMediaInfo {
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        // Create download task with progress
        let (tempURL, _) = try await downloadWithProgress(url: url, onProgress: onProgress)

        // Move to project storage
        let destinationURL = try await FileStorageService.shared.copyMediaToProject(
            sourceURL: tempURL,
            projectId: projectId
        )

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        // Get video info
        let asset = AVURLAsset(url: destinationURL)
        let duration = try await asset.load(.duration)

        var naturalSize = CGSize(width: 1080, height: 1920)
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            let transformedSize = naturalSize.applying(transform)
            naturalSize = CGSize(
                width: abs(transformedSize.width),
                height: abs(transformedSize.height)
            )
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let hasAudio = !audioTracks.isEmpty

        return ImportedMediaInfo(
            url: destinationURL,
            duration: duration,
            naturalSize: naturalSize,
            hasAudio: hasAudio
        )
    }

    private func downloadWithProgress(url: URL, onProgress: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        // Use URLSession for download with progress tracking
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)

        let (asyncBytes, response) = try await session.bytes(from: url)

        let expectedLength = response.expectedContentLength
        var receivedLength: Int64 = 0

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")

        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempFile)

        // Download in chunks
        var buffer = Data()
        let bufferSize = 65536 // 64KB chunks

        for try await byte in asyncBytes {
            buffer.append(byte)
            receivedLength += 1

            if buffer.count >= bufferSize {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)

                if expectedLength > 0 {
                    let progress = Double(receivedLength) / Double(expectedLength)
                    await MainActor.run {
                        onProgress(progress)
                    }
                }
            }
        }

        // Write remaining buffer
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }

        try fileHandle.close()

        await MainActor.run {
            onProgress(1.0)
        }

        return (tempFile, response)
    }
}

// MARK: - Sample Video URLs for Testing

enum SampleVideos {
    static let videos: [(name: String, url: String)] = [
        // Short test videos - best for quick testing
        ("For Bigger Blazes (15s)", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"),
        ("For Bigger Escapes (15s)", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4"),

        // Blender Foundation - Big Buck Bunny (public domain)
        ("Big Buck Bunny (1min)", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"),

        // Blender Foundation - Sintel (public domain)
        ("Sintel Trailer", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"),

        // Blender Foundation - Elephant's Dream
        ("Elephant's Dream", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4"),

        // Tears of Steel
        ("Tears of Steel", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4"),

        // More short clips
        ("For Bigger Fun (1min)", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"),
        ("Subaru Outback (10s)", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4"),
    ]
}
