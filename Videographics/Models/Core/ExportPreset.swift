//
//  ExportPreset.swift
//  Videographics
//

import Foundation
import CoreMedia

/// Export quality levels
enum ExportQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case maximum = "Maximum"

    var id: String { rawValue }

    var videoBitrate: Int {
        switch self {
        case .low: return 5_000_000      // 5 Mbps
        case .medium: return 10_000_000   // 10 Mbps
        case .high: return 20_000_000     // 20 Mbps
        case .maximum: return 35_000_000  // 35 Mbps
        }
    }

    var audioBitrate: Int {
        switch self {
        case .low: return 128_000
        case .medium: return 192_000
        case .high: return 256_000
        case .maximum: return 320_000
        }
    }
}

/// Platform-specific export presets
enum ExportPlatform: String, CaseIterable, Identifiable {
    case instagramStory = "Instagram Story"
    case instagramReel = "Instagram Reel"
    case tiktok = "TikTok"
    case youtubeShorts = "YouTube Shorts"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .instagramStory, .instagramReel: return "camera"
        case .tiktok: return "music.note"
        case .youtubeShorts: return "play.rectangle"
        case .custom: return "slider.horizontal.3"
        }
    }

    var maxDuration: CMTime? {
        switch self {
        case .instagramStory: return CMTime(seconds: 60, preferredTimescale: 600)
        case .instagramReel: return CMTime(seconds: 90, preferredTimescale: 600)
        case .tiktok: return CMTime(seconds: 180, preferredTimescale: 600) // 3 minutes
        case .youtubeShorts: return CMTime(seconds: 60, preferredTimescale: 600)
        case .custom: return nil
        }
    }

    var maxDurationDescription: String? {
        guard let maxDuration = maxDuration else { return nil }
        let seconds = Int(maxDuration.seconds)
        if seconds >= 60 {
            return "\(seconds / 60) min"
        }
        return "\(seconds)s"
    }
}

/// Complete export configuration
struct ExportPreset: Identifiable, Equatable {
    let id = UUID()
    var platform: ExportPlatform
    var resolution: CGSize
    var frameRate: Int
    var quality: ExportQuality

    /// Default presets for each platform
    static let instagramStory = ExportPreset(
        platform: .instagramStory,
        resolution: CGSize(width: 1080, height: 1920),
        frameRate: 30,
        quality: .high
    )

    static let instagramReel = ExportPreset(
        platform: .instagramReel,
        resolution: CGSize(width: 1080, height: 1920),
        frameRate: 30,
        quality: .high
    )

    static let tiktok = ExportPreset(
        platform: .tiktok,
        resolution: CGSize(width: 1080, height: 1920),
        frameRate: 30,
        quality: .high
    )

    static let youtubeShorts = ExportPreset(
        platform: .youtubeShorts,
        resolution: CGSize(width: 1080, height: 1920),
        frameRate: 30,
        quality: .high
    )

    static let custom = ExportPreset(
        platform: .custom,
        resolution: CGSize(width: 1080, height: 1920),
        frameRate: 30,
        quality: .high
    )

    /// All default presets
    static let allPresets: [ExportPreset] = [
        .tiktok,
        .instagramReel,
        .instagramStory,
        .youtubeShorts,
        .custom
    ]

    /// Get preset for platform
    static func preset(for platform: ExportPlatform) -> ExportPreset {
        switch platform {
        case .instagramStory: return .instagramStory
        case .instagramReel: return .instagramReel
        case .tiktok: return .tiktok
        case .youtubeShorts: return .youtubeShorts
        case .custom: return .custom
        }
    }

    var aspectRatio: CGFloat {
        resolution.width / resolution.height
    }

    var resolutionDescription: String {
        "\(Int(resolution.width))×\(Int(resolution.height))"
    }

    var frameDuration: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
}
