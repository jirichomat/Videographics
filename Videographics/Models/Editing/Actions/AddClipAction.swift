//
//  AddClipAction.swift
//  Videographics
//

import Foundation

/// Action for adding a clip to a layer
@MainActor
final class AddClipAction: EditAction {
    let actionDescription: String = "Add Clip"

    private weak var clip: VideoClip?
    private weak var layer: VideoLayer?
    private let clipId: UUID

    init(clip: VideoClip, layer: VideoLayer) {
        self.clip = clip
        self.layer = layer
        self.clipId = clip.id
    }

    func execute() {
        guard let clip = clip, let layer = layer else { return }

        // Only add if not already in the layer
        if !layer.clips.contains(where: { $0.id == clipId }) {
            layer.addClip(clip)
        }
    }

    func undo() {
        guard let clip = clip, let layer = layer else { return }
        layer.removeClip(clip)
    }
}
