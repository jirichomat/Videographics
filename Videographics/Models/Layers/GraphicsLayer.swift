//
//  GraphicsLayer.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class GraphicsLayer {
    var id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \GraphicsClip.layer)
    var clips: [GraphicsClip]

    var timeline: Timeline?

    init(name: String, zIndex: Int) {
        self.id = UUID()
        self.name = name
        self.isVisible = true
        self.isLocked = false
        self.zIndex = zIndex
        self.clips = []
    }

    func addClip(_ clip: GraphicsClip) {
        clips.append(clip)
    }

    func removeClip(_ clip: GraphicsClip) {
        clips.removeAll { $0.id == clip.id }
    }

    /// Get clips sorted by timeline start time
    var sortedClips: [GraphicsClip] {
        clips.sorted { $0.timelineStartTimeValue < $1.timelineStartTimeValue }
    }
}
