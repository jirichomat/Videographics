//
//  AudioClip.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class AudioClip {
    var id: UUID

    // Asset reference
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

    // Volume (0.0 to 1.0)
    var volume: Float

    // Is muted
    var isMuted: Bool

    var layer: AudioLayer?

    init(
        assetURL: URL,
        timelineStartTime: CMTime = .zero,
        duration: CMTime,
        sourceStartTime: CMTime = .zero
    ) {
        self.id = UUID()
        self.assetURLString = assetURL.absoluteString

        self.timelineStartTimeValue = timelineStartTime.value
        self.timelineStartTimeScale = timelineStartTime.timescale

        self.durationValue = duration.value
        self.durationScale = duration.timescale

        self.sourceStartTimeValue = sourceStartTime.value
        self.sourceStartTimeScale = sourceStartTime.timescale

        self.volume = 1.0
        self.isMuted = false
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

    var cmTimelineEndTime: CMTime {
        CMTimeAdd(cmTimelineStartTime, cmDuration)
    }

    var assetURL: URL? {
        URL(string: assetURLString)
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
}
