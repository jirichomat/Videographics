//
//  AudioLayer.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class AudioLayer {
    var id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \AudioClip.layer)
    var clips: [AudioClip]

    var timeline: Timeline?

    init(name: String, zIndex: Int) {
        self.id = UUID()
        self.name = name
        self.isVisible = true
        self.isLocked = false
        self.zIndex = zIndex
        self.clips = []
    }

    func addClip(_ clip: AudioClip) {
        clips.append(clip)
    }

    func removeClip(_ clip: AudioClip) {
        clips.removeAll { $0.id == clip.id }
    }

    /// Get clips sorted by timeline start time
    var sortedClips: [AudioClip] {
        clips.sorted { $0.timelineStartTimeValue < $1.timelineStartTimeValue }
    }
}
