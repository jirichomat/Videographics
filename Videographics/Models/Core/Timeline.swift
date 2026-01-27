//
//  Timeline.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class Timeline {
    var id: UUID

    @Relationship(deleteRule: .cascade, inverse: \VideoLayer.timeline)
    var videoLayers: [VideoLayer]

    @Relationship(deleteRule: .cascade, inverse: \AudioLayer.timeline)
    var audioLayers: [AudioLayer]

    init() {
        self.id = UUID()
        self.videoLayers = []
        self.audioLayers = []

        // Create default layers
        let mainVideoLayer = VideoLayer(name: "V1", zIndex: 0)
        let pipVideoLayer = VideoLayer(name: "V2", zIndex: 1)
        let mainAudioLayer = AudioLayer(name: "Audio", zIndex: -1)

        self.videoLayers.append(mainVideoLayer)
        self.videoLayers.append(pipVideoLayer)
        self.audioLayers.append(mainAudioLayer)
    }

    var duration: CMTime {
        var maxDuration: CMTime = .zero

        for layer in videoLayers {
            for clip in layer.clips {
                let clipEnd = CMTimeAdd(clip.cmTimelineStartTime, clip.cmDuration)
                if CMTimeCompare(clipEnd, maxDuration) > 0 {
                    maxDuration = clipEnd
                }
            }
        }

        for layer in audioLayers {
            for clip in layer.clips {
                let clipEnd = CMTimeAdd(clip.cmTimelineStartTime, clip.cmDuration)
                if CMTimeCompare(clipEnd, maxDuration) > 0 {
                    maxDuration = clipEnd
                }
            }
        }

        return maxDuration
    }

    var mainVideoLayer: VideoLayer? {
        videoLayers.first { $0.zIndex == 0 }
    }

    var mainAudioLayer: AudioLayer? {
        audioLayers.first
    }

    var isEmpty: Bool {
        let hasVideoClips = videoLayers.contains { !$0.clips.isEmpty }
        let hasAudioClips = audioLayers.contains { !$0.clips.isEmpty }
        return !hasVideoClips && !hasAudioClips
    }

    func addVideoLayer(name: String) -> VideoLayer {
        let maxZIndex = videoLayers.map { $0.zIndex }.max() ?? 0
        let layer = VideoLayer(name: name, zIndex: maxZIndex + 1)
        videoLayers.append(layer)
        return layer
    }

    func addAudioLayer(name: String) -> AudioLayer {
        let minZIndex = audioLayers.map { $0.zIndex }.min() ?? 0
        let layer = AudioLayer(name: name, zIndex: minZIndex - 1)
        audioLayers.append(layer)
        return layer
    }
}
