//
//  SplitClipAction.swift
//  Videographics
//

import Foundation
import CoreMedia

/// Action for splitting a clip into two clips
@MainActor
final class SplitClipAction: EditAction {
    let actionDescription: String = "Split Clip"

    /// The original clip (first part after split)
    private weak var originalClip: VideoClip?

    /// The second clip created by the split (strong reference to survive undo/redo)
    private var secondClip: VideoClip?

    /// The layer containing the clips
    private weak var layer: VideoLayer?

    /// Original duration before split
    private let originalDurationValue: Int64
    private let originalDurationScale: Int32

    /// Duration of the first clip after split (for redo)
    private let splitDurationValue: Int64
    private let splitDurationScale: Int32

    init(originalClip: VideoClip, secondClip: VideoClip, layer: VideoLayer, originalDuration: CMTime) {
        self.originalClip = originalClip
        self.secondClip = secondClip
        self.layer = layer
        self.originalDurationValue = originalDuration.value
        self.originalDurationScale = originalDuration.timescale
        // Capture the split duration for redo
        self.splitDurationValue = originalClip.durationValue
        self.splitDurationScale = originalClip.durationScale
    }

    func execute() {
        guard let originalClip = originalClip,
              let layer = layer,
              let secondClip = secondClip else { return }

        // Restore the split state
        originalClip.durationValue = splitDurationValue
        originalClip.durationScale = splitDurationScale

        // Add second clip back if not present
        if !layer.clips.contains(where: { $0.id == secondClip.id }) {
            layer.addClip(secondClip)
        }
    }

    func undo() {
        guard let originalClip = originalClip,
              let layer = layer,
              let secondClip = secondClip else { return }

        // Restore original clip's duration
        originalClip.durationValue = originalDurationValue
        originalClip.durationScale = originalDurationScale

        // Remove the second clip
        layer.removeClip(secondClip)
    }
}
