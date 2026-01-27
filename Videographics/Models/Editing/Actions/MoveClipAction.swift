//
//  MoveClipAction.swift
//  Videographics
//

import Foundation
import CoreMedia

/// Action for moving a clip on the timeline (changing timeline start time)
@MainActor
final class MoveClipAction: EditAction {
    let actionDescription: String = "Move Clip"

    private weak var clip: VideoClip?
    private let originalTimelineStartTimeValue: Int64
    private let originalTimelineStartTimeScale: Int32
    private let newTimelineStartTimeValue: Int64
    private let newTimelineStartTimeScale: Int32

    /// Initialize with before/after state
    init(clip: VideoClip, originalStartTime: CMTime, newStartTime: CMTime) {
        self.clip = clip
        self.originalTimelineStartTimeValue = originalStartTime.value
        self.originalTimelineStartTimeScale = originalStartTime.timescale
        self.newTimelineStartTimeValue = newStartTime.value
        self.newTimelineStartTimeScale = newStartTime.timescale
    }

    /// Check if the action represents an actual change
    var hasChange: Bool {
        originalTimelineStartTimeValue != newTimelineStartTimeValue ||
        originalTimelineStartTimeScale != newTimelineStartTimeScale
    }

    func execute() {
        guard let clip = clip else { return }
        clip.timelineStartTimeValue = newTimelineStartTimeValue
        clip.timelineStartTimeScale = newTimelineStartTimeScale
    }

    func undo() {
        guard let clip = clip else { return }
        clip.timelineStartTimeValue = originalTimelineStartTimeValue
        clip.timelineStartTimeScale = originalTimelineStartTimeScale
    }
}
