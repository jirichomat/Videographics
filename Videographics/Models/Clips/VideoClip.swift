//
//  VideoClip.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia
import AVFoundation

/// Defines how the video fills the canvas
enum VideoScaleMode: String, Codable, CaseIterable {
    case fit       // Fit within canvas, may have letterboxing
    case fill      // Fill canvas, may crop edges
    case stretch   // Stretch to fill (distorts aspect)

    var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }
}

@Model
final class VideoClip {
    var id: UUID

    // Asset reference (stored as file URL string)
    var assetURLString: String

    // Timeline position (CMTime stored as Int64/Int32 for SwiftData)
    var timelineStartTimeValue: Int64
    var timelineStartTimeScale: Int32

    // Duration on timeline
    var durationValue: Int64
    var durationScale: Int32

    // Source media trim points
    var sourceStartTimeValue: Int64
    var sourceStartTimeScale: Int32

    // Original asset duration
    var originalDurationValue: Int64
    var originalDurationScale: Int32

    // Volume (0.0 to 1.0)
    var volume: Float

    // Scale mode (stored as String for SwiftData)
    var scaleModeRaw: String

    // Manual scale factor (1.0 = 100%)
    var scale: Float

    // Position offset from center (normalized -1 to 1)
    var positionX: Float
    var positionY: Float

    // Original video dimensions (for transform calculations)
    var sourceWidth: Int
    var sourceHeight: Int

    // Thumbnail data (stored as Data for SwiftData)
    var thumbnailsData: Data?

    // Transition to next clip (outgoing transition)
    var outTransition: Transition?

    var layer: VideoLayer?

    init(
        assetURL: URL,
        timelineStartTime: CMTime = .zero,
        duration: CMTime,
        sourceStartTime: CMTime = .zero,
        scaleMode: VideoScaleMode = .fill,
        sourceSize: CGSize = .zero
    ) {
        self.id = UUID()
        self.assetURLString = assetURL.absoluteString

        self.timelineStartTimeValue = timelineStartTime.value
        self.timelineStartTimeScale = timelineStartTime.timescale

        self.durationValue = duration.value
        self.durationScale = duration.timescale

        self.sourceStartTimeValue = sourceStartTime.value
        self.sourceStartTimeScale = sourceStartTime.timescale

        self.originalDurationValue = duration.value
        self.originalDurationScale = duration.timescale

        self.volume = 1.0

        // Scale/transform defaults
        self.scaleModeRaw = scaleMode.rawValue
        self.scale = 1.0
        self.positionX = 0.0
        self.positionY = 0.0
        self.sourceWidth = Int(sourceSize.width)
        self.sourceHeight = Int(sourceSize.height)
    }

    // MARK: - CMTime Computed Properties

    var cmTimelineStartTime: CMTime {
        CMTime(value: timelineStartTimeValue, timescale: timelineStartTimeScale)
    }

    var cmDuration: CMTime {
        CMTime(value: durationValue, timescale: durationScale)
    }

    var cmSourceStartTime: CMTime {
        CMTime(value: sourceStartTimeValue, timescale: sourceStartTimeScale)
    }

    var cmOriginalDuration: CMTime {
        CMTime(value: originalDurationValue, timescale: originalDurationScale)
    }

    var cmTimelineEndTime: CMTime {
        CMTimeAdd(cmTimelineStartTime, cmDuration)
    }

    var assetURL: URL? {
        guard let originalURL = URL(string: assetURLString) else { return nil }

        // If file exists at original path, use it
        if FileManager.default.fileExists(atPath: originalURL.path) {
            return originalURL
        }

        // Try to resolve relative path from Documents directory
        // Expected format: .../Documents/Projects/{projectId}/Media/{filename}.mp4
        let pathComponents = originalURL.pathComponents
        if let documentsIndex = pathComponents.firstIndex(of: "Documents"),
           documentsIndex + 1 < pathComponents.count {
            // Extract relative path after Documents
            let relativePath = pathComponents[(documentsIndex + 1)...].joined(separator: "/")
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            if let resolvedURL = documentsURL?.appendingPathComponent(relativePath),
               FileManager.default.fileExists(atPath: resolvedURL.path) {
                // Update stored path for future access
                assetURLString = resolvedURL.absoluteString
                return resolvedURL
            }
        }

        return originalURL
    }

    // MARK: - Scale Properties

    var scaleMode: VideoScaleMode {
        get { VideoScaleMode(rawValue: scaleModeRaw) ?? .fill }
        set { scaleModeRaw = newValue.rawValue }
    }

    var sourceSize: CGSize {
        get { CGSize(width: sourceWidth, height: sourceHeight) }
        set {
            sourceWidth = Int(newValue.width)
            sourceHeight = Int(newValue.height)
        }
    }

    /// Calculate the transform needed to display this clip in the target render size
    func calculateTransform(for renderSize: CGSize) -> CGAffineTransform {
        guard sourceWidth > 0 && sourceHeight > 0 else {
            return .identity
        }

        let sourceAspect = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let targetAspect = renderSize.width / renderSize.height

        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0

        switch scaleMode {
        case .fit:
            // Scale to fit within bounds (may have letterboxing)
            if sourceAspect > targetAspect {
                // Video is wider - fit to width
                scaleX = renderSize.width / CGFloat(sourceWidth)
                scaleY = scaleX
            } else {
                // Video is taller - fit to height
                scaleY = renderSize.height / CGFloat(sourceHeight)
                scaleX = scaleY
            }

        case .fill:
            // Scale to fill bounds (may crop)
            if sourceAspect > targetAspect {
                // Video is wider - fit to height, crop width
                scaleY = renderSize.height / CGFloat(sourceHeight)
                scaleX = scaleY
            } else {
                // Video is taller - fit to width, crop height
                scaleX = renderSize.width / CGFloat(sourceWidth)
                scaleY = scaleX
            }

        case .stretch:
            // Stretch to exactly fill (distorts)
            scaleX = renderSize.width / CGFloat(sourceWidth)
            scaleY = renderSize.height / CGFloat(sourceHeight)
        }

        // Apply manual scale adjustment
        scaleX *= CGFloat(scale)
        scaleY *= CGFloat(scale)

        // Calculate translation to center the video
        let scaledWidth = CGFloat(sourceWidth) * scaleX
        let scaledHeight = CGFloat(sourceHeight) * scaleY
        let translateX = (renderSize.width - scaledWidth) / 2 + CGFloat(positionX) * renderSize.width / 2
        let translateY = (renderSize.height - scaledHeight) / 2 + CGFloat(positionY) * renderSize.height / 2

        return CGAffineTransform(translationX: translateX, y: translateY)
            .scaledBy(x: scaleX, y: scaleY)
    }

    // MARK: - Setters

    func setTimelineStartTime(_ time: CMTime) {
        timelineStartTimeValue = time.value
        timelineStartTimeScale = time.timescale
    }

    func setDuration(_ time: CMTime) {
        durationValue = time.value
        durationScale = time.timescale
    }

    func setSourceStartTime(_ time: CMTime) {
        sourceStartTimeValue = time.value
        sourceStartTimeScale = time.timescale
    }

    // MARK: - Thumbnails

    var thumbnails: [Data] {
        get {
            guard let data = thumbnailsData else { return [] }
            return (try? JSONDecoder().decode([Data].self, from: data)) ?? []
        }
        set {
            thumbnailsData = try? JSONEncoder().encode(newValue)
        }
    }
}
