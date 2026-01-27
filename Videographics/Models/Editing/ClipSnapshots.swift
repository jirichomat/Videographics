//
//  ClipSnapshots.swift
//  Videographics
//

import Foundation
import CoreMedia

/// Snapshot of a video clip's timing properties
struct VideoClipTimingSnapshot {
    let timelineStartTimeValue: Int64
    let timelineStartTimeScale: Int32
    let durationValue: Int64
    let durationScale: Int32
    let sourceStartTimeValue: Int64
    let sourceStartTimeScale: Int32

    init(from clip: VideoClip) {
        self.timelineStartTimeValue = clip.timelineStartTimeValue
        self.timelineStartTimeScale = clip.timelineStartTimeScale
        self.durationValue = clip.durationValue
        self.durationScale = clip.durationScale
        self.sourceStartTimeValue = clip.sourceStartTimeValue
        self.sourceStartTimeScale = clip.sourceStartTimeScale
    }

    /// Apply this snapshot to a clip
    func apply(to clip: VideoClip) {
        clip.timelineStartTimeValue = timelineStartTimeValue
        clip.timelineStartTimeScale = timelineStartTimeScale
        clip.durationValue = durationValue
        clip.durationScale = durationScale
        clip.sourceStartTimeValue = sourceStartTimeValue
        clip.sourceStartTimeScale = sourceStartTimeScale
    }

    var cmTimelineStartTime: CMTime {
        CMTime(value: timelineStartTimeValue, timescale: timelineStartTimeScale)
    }

    var cmDuration: CMTime {
        CMTime(value: durationValue, timescale: durationScale)
    }

    var cmSourceStartTime: CMTime {
        CMTime(value: sourceStartTimeValue, timescale: sourceStartTimeScale)
    }
}

/// Snapshot of a video clip's transform properties
struct VideoClipTransformSnapshot {
    let scaleModeRaw: String
    let scale: Float
    let positionX: Float
    let positionY: Float

    init(from clip: VideoClip) {
        self.scaleModeRaw = clip.scaleModeRaw
        self.scale = clip.scale
        self.positionX = clip.positionX
        self.positionY = clip.positionY
    }

    /// Apply this snapshot to a clip
    func apply(to clip: VideoClip) {
        clip.scaleModeRaw = scaleModeRaw
        clip.scale = scale
        clip.positionX = positionX
        clip.positionY = positionY
    }
}

/// Complete snapshot of a video clip's state for delete/restore operations
struct VideoClipFullSnapshot {
    let id: UUID
    let assetURLString: String
    let timelineStartTimeValue: Int64
    let timelineStartTimeScale: Int32
    let durationValue: Int64
    let durationScale: Int32
    let sourceStartTimeValue: Int64
    let sourceStartTimeScale: Int32
    let originalDurationValue: Int64
    let originalDurationScale: Int32
    let volume: Float
    let scaleModeRaw: String
    let scale: Float
    let positionX: Float
    let positionY: Float
    let sourceWidth: Int
    let sourceHeight: Int
    let thumbnailsData: Data?
    let layerId: UUID

    init?(from clip: VideoClip) {
        guard let layer = clip.layer else { return nil }

        self.id = clip.id
        self.assetURLString = clip.assetURLString
        self.timelineStartTimeValue = clip.timelineStartTimeValue
        self.timelineStartTimeScale = clip.timelineStartTimeScale
        self.durationValue = clip.durationValue
        self.durationScale = clip.durationScale
        self.sourceStartTimeValue = clip.sourceStartTimeValue
        self.sourceStartTimeScale = clip.sourceStartTimeScale
        self.originalDurationValue = clip.originalDurationValue
        self.originalDurationScale = clip.originalDurationScale
        self.volume = clip.volume
        self.scaleModeRaw = clip.scaleModeRaw
        self.scale = clip.scale
        self.positionX = clip.positionX
        self.positionY = clip.positionY
        self.sourceWidth = clip.sourceWidth
        self.sourceHeight = clip.sourceHeight
        self.thumbnailsData = clip.thumbnailsData
        self.layerId = layer.id
    }

    /// Create a new VideoClip from this snapshot
    func createClip() -> VideoClip {
        guard let url = URL(string: assetURLString) else {
            fatalError("Invalid asset URL in snapshot")
        }

        let clip = VideoClip(
            assetURL: url,
            timelineStartTime: CMTime(value: timelineStartTimeValue, timescale: timelineStartTimeScale),
            duration: CMTime(value: durationValue, timescale: durationScale),
            sourceStartTime: CMTime(value: sourceStartTimeValue, timescale: sourceStartTimeScale),
            scaleMode: VideoScaleMode(rawValue: scaleModeRaw) ?? .fill,
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight)
        )

        // Restore the original ID
        clip.id = id

        // Restore additional properties
        clip.originalDurationValue = originalDurationValue
        clip.originalDurationScale = originalDurationScale
        clip.volume = volume
        clip.scale = scale
        clip.positionX = positionX
        clip.positionY = positionY
        clip.thumbnailsData = thumbnailsData

        return clip
    }
}
