//
//  DeleteClipAction.swift
//  Videographics
//

import Foundation

/// Action for deleting a clip from a layer
@MainActor
final class DeleteClipAction: EditAction {
    let actionDescription: String = "Delete Clip"

    /// Snapshot of the deleted clip for restoration
    private let snapshot: VideoClipFullSnapshot

    /// Weak reference to the layer (may be deleted)
    private weak var layer: VideoLayer?

    /// Strong reference to the clip (survives undo/redo cycles)
    private var clip: VideoClip?

    init?(clip: VideoClip, layer: VideoLayer) {
        guard let snapshot = VideoClipFullSnapshot(from: clip) else { return nil }
        self.snapshot = snapshot
        self.layer = layer
        self.clip = clip
    }

    func execute() {
        guard let layer = layer else { return }

        // Use existing clip reference or find by ID
        if let clip = self.clip {
            layer.removeClip(clip)
        } else if let clip = layer.clips.first(where: { $0.id == snapshot.id }) {
            layer.removeClip(clip)
            self.clip = clip
        }
    }

    func undo() {
        guard let layer = layer else { return }

        // Use existing clip reference or create from snapshot
        let clipToRestore: VideoClip
        if let existingClip = self.clip {
            clipToRestore = existingClip
        } else {
            clipToRestore = snapshot.createClip()
            self.clip = clipToRestore
        }

        // Add clip back to layer if not already present
        if !layer.clips.contains(where: { $0.id == clipToRestore.id }) {
            layer.addClip(clipToRestore)
        }
    }
}
