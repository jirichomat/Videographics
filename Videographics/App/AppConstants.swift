//
//  AppConstants.swift
//  Videographics
//

import Foundation
import CoreMedia

enum AppConstants {
    // MARK: - Timeline
    static let defaultPixelsPerSecond: CGFloat = 50.0
    static let minPixelsPerSecond: CGFloat = 10.0
    static let maxPixelsPerSecond: CGFloat = 200.0

    // MARK: - Video
    static let defaultAspectRatio: CGFloat = 9.0 / 16.0 // Portrait
    static let defaultResolution = CGSize(width: 1080, height: 1920)

    // MARK: - Transitions
    static let defaultTransitionDuration: CMTime = CMTime(seconds: 0.5, preferredTimescale: 600)

    // MARK: - Thumbnails
    static let thumbnailSize = CGSize(width: 60, height: 106) // 9:16 aspect
    static let thumbnailsPerClip = 10

    // MARK: - Playback
    static let playbackTimescale: CMTimeScale = 600

    // MARK: - Track Heights
    static let videoTrackHeight: CGFloat = 60.0
    static let audioTrackHeight: CGFloat = 40.0
    static let textTrackHeight: CGFloat = 40.0
    static let graphicsTrackHeight: CGFloat = 40.0
    static let infographicTrackHeight: CGFloat = 40.0
    static let overlayTrackHeight: CGFloat = 40.0

    // MARK: - UI
    static let timeRulerHeight: CGFloat = 30.0
    static let trackLabelWidth: CGFloat = 50.0
    static let playheadWidth: CGFloat = 2.0
}
