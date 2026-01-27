//
//  InfographicLayer.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class InfographicLayer {
    var id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \InfographicClip.layer)
    var clips: [InfographicClip]

    var timeline: Timeline?

    init(name: String, zIndex: Int) {
        self.id = UUID()
        self.name = name
        self.isVisible = true
        self.isLocked = false
        self.zIndex = zIndex
        self.clips = []
    }

    func addClip(_ clip: InfographicClip) {
        clips.append(clip)
    }

    func removeClip(_ clip: InfographicClip) {
        clips.removeAll { $0.id == clip.id }
    }

    /// Get clips sorted by timeline start time
    var sortedClips: [InfographicClip] {
        clips.sorted { $0.timelineStartTimeValue < $1.timelineStartTimeValue }
    }
}
