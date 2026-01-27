//
//  TransformClipAction.swift
//  Videographics
//

import Foundation

/// Action for changing a clip's transform properties (scale mode, scale, position)
@MainActor
final class TransformClipAction: EditAction {
    let actionDescription: String = "Transform Clip"

    private weak var clip: VideoClip?
    private let beforeSnapshot: VideoClipTransformSnapshot
    private let afterSnapshot: VideoClipTransformSnapshot

    /// Initialize with before/after transform snapshots
    init(clip: VideoClip, beforeSnapshot: VideoClipTransformSnapshot, afterSnapshot: VideoClipTransformSnapshot) {
        self.clip = clip
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
    }

    /// Check if the action represents an actual change
    var hasChange: Bool {
        beforeSnapshot.scaleModeRaw != afterSnapshot.scaleModeRaw ||
        beforeSnapshot.scale != afterSnapshot.scale ||
        beforeSnapshot.positionX != afterSnapshot.positionX ||
        beforeSnapshot.positionY != afterSnapshot.positionY
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
