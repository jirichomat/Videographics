//
//  ThumbnailGenerator.swift
//  Videographics
//

import Foundation
import AVFoundation
import UIKit
import CoreMedia

actor ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    // Local copies to avoid main actor isolation issues
    private let thumbnailSize = CGSize(width: 60, height: 106)
    private let thumbnailsPerClip = 10

    /// Generate thumbnails for a video clip
    func generateThumbnails(for url: URL, duration: CMTime) async -> [Data] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: thumbnailSize.width * 2, // 2x for retina
            height: thumbnailSize.height * 2
        )

        var thumbnails: [Data] = []
        let durationSeconds = duration.seconds

        guard durationSeconds > 0 else { return [] }

        let count = min(thumbnailsPerClip, max(1, Int(durationSeconds)))
        let interval = durationSeconds / Double(count)

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let uiImage = UIImage(cgImage: cgImage)
                if let data = uiImage.jpegData(compressionQuality: 0.6) {
                    thumbnails.append(data)
                }
            } catch {
                // Skip failed thumbnails
                continue
            }
        }

        return thumbnails
    }

    /// Generate a single thumbnail at a specific time
    func generateThumbnail(for url: URL, at time: CMTime) async -> Data? {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ThumbnailGenerator: File does not exist at \(url.path)")
            return nil
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: thumbnailSize.width * 2,
            height: thumbnailSize.height * 2
        )
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        do {
            // Ensure asset is readable
            let status = try await asset.load(.isReadable)
            guard status else {
                print("ThumbnailGenerator: Asset is not readable")
                return nil
            }

            let (cgImage, _) = try await generator.image(at: time)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            print("ThumbnailGenerator: Failed to generate thumbnail - \(error.localizedDescription)")
            return nil
        }
    }
}
