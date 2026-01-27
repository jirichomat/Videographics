//
//  GraphicsClip.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class GraphicsClip {
    var id: UUID

    // Image data stored directly (for imported stickers/images)
    var imageData: Data?

    // Or reference to file URL (for larger images)
    var imageURLString: String?

    // Position (normalized -1 to 1, center is 0,0)
    var positionX: Float
    var positionY: Float

    // Scale factor (1.0 = 100%)
    var scale: Float

    // Rotation in degrees
    var rotation: Float

    // Opacity (0.0 to 1.0)
    var opacity: Float

    // Original image dimensions
    var sourceWidth: Int
    var sourceHeight: Int

    // Timeline position (CMTime stored as Int64/Int32 for SwiftData)
    var timelineStartTimeValue: Int64
    var timelineStartTimeScale: Int32

    // Duration on timeline
    var durationValue: Int64
    var durationScale: Int32

    var layer: GraphicsLayer?

    init(
        imageData: Data? = nil,
        imageURL: URL? = nil,
        timelineStartTime: CMTime = .zero,
        duration: CMTime = CMTime(seconds: 5.0, preferredTimescale: 600),
        sourceSize: CGSize = .zero,
        positionX: Float = 0,
        positionY: Float = 0
    ) {
        self.id = UUID()
        self.imageData = imageData
        self.imageURLString = imageURL?.absoluteString
        self.positionX = positionX
        self.positionY = positionY
        self.scale = 1.0
        self.rotation = 0
        self.opacity = 1.0
        self.sourceWidth = Int(sourceSize.width)
        self.sourceHeight = Int(sourceSize.height)

        self.timelineStartTimeValue = timelineStartTime.value
        self.timelineStartTimeScale = timelineStartTime.timescale
        self.durationValue = duration.value
        self.durationScale = duration.timescale
    }

    // MARK: - CMTime Computed Properties

    var cmTimelineStartTime: CMTime {
        CMTime(value: timelineStartTimeValue, timescale: timelineStartTimeScale)
    }

    var cmDuration: CMTime {
        CMTime(value: durationValue, timescale: durationScale)
    }

    var cmTimelineEndTime: CMTime {
        CMTimeAdd(cmTimelineStartTime, cmDuration)
    }

    // MARK: - Image Access

    var imageURL: URL? {
        guard let urlString = imageURLString else { return nil }
        return URL(string: urlString)
    }

    var sourceSize: CGSize {
        get { CGSize(width: sourceWidth, height: sourceHeight) }
        set {
            sourceWidth = Int(newValue.width)
            sourceHeight = Int(newValue.height)
        }
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
}
