//
//  TrimClipAction.swift
//  Videographics
//

import Foundation
import CoreMedia

/// Action for trimming a clip (changing timing properties)
@MainActor
final class TrimClipAction: EditAction {
    let actionDescription: String = "Trim Clip"

    private weak var clip: VideoClip?
    private let beforeSnapshot: VideoClipTimingSnapshot
    private let afterSnapshot: VideoClipTimingSnapshot

    /// Initialize with before/after timing snapshots
    init(clip: VideoClip, beforeSnapshot: VideoClipTimingSnapshot, afterSnapshot: VideoClipTimingSnapshot) {
        self.clip = clip
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
    }

    /// Check if the action represents an actual change
    var hasChange: Bool {
        beforeSnapshot.timelineStartTimeValue != afterSnapshot.timelineStartTimeValue ||
        beforeSnapshot.durationValue != afterSnapshot.durationValue ||
        beforeSnapshot.sourceStartTimeValue != afterSnapshot.sourceStartTimeValue
    }

    func execute() {
        guard let clip = clip else { return }
        afterSnapshot.apply(to: clip)
    }

    func undo() {
        guard let clip = clip else { return }
        beforeSnapshot.apply(to: clip)
    }
}
