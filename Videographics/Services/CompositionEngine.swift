//
//  CompositionEngine.swift
//  Videographics
//

import Foundation
import AVFoundation
import CoreMedia

/// Holds composition build result with both composition and video composition
struct CompositionResult {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
}

actor CompositionEngine {
    static let shared = CompositionEngine()

    // Store clip info during composition building for video composition creation
    private struct ClipTrackInfo {
        let clip: VideoClip
        let trackID: CMPersistentTrackID
        let timeRange: CMTimeRange
        let transition: Transition?  // Outgoing transition (if any)
    }

    /// Build an AVMutableComposition from a Timeline
    func buildComposition(from timeline: Timeline, renderSize: CGSize = AppConstants.defaultResolution) async -> CompositionResult? {
        let composition = AVMutableComposition()
        var clipInfos: [ClipTrackInfo] = []

        // Process video layers (sorted by z-index)
        let sortedVideoLayers = timeline.videoLayers.sorted { $0.zIndex < $1.zIndex }

        for (layerIndex, layer) in sortedVideoLayers.enumerated() {
            guard layer.isVisible else { continue }

            let trackID = CMPersistentTrackID(layerIndex + 1)

            // Create video and audio tracks for this layer
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else { continue }

            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: CMPersistentTrackID(100 + layerIndex)
            )

            // Add clips to the tracks
            for clip in layer.sortedClips {
                if let info = await addClipToTrack(
                    clip: clip,
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    trackID: trackID
                ) {
                    clipInfos.append(info)
                }
            }
        }

        // Process standalone audio layers
        for (layerIndex, layer) in timeline.audioLayers.enumerated() {
            guard layer.isVisible else { continue }

            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: CMPersistentTrackID(200 + layerIndex)
            ) else { continue }

            for clip in layer.sortedClips {
                await addAudioClipToTrack(clip: clip, audioTrack: audioTrack)
            }
        }

        // Build video composition with transforms
        let videoComposition = buildVideoComposition(
            for: composition,
            clipInfos: clipInfos,
            renderSize: renderSize
        )

        return CompositionResult(composition: composition, videoComposition: videoComposition)
    }

    private func addClipToTrack(
        clip: VideoClip,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        trackID: CMPersistentTrackID
    ) async -> ClipTrackInfo? {
        guard let assetURL = clip.assetURL else { return nil }

        let asset = AVURLAsset(url: assetURL)

        do {
            // Load video tracks
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first else { return nil }

            // Define the time range from the source
            let sourceTimeRange = CMTimeRange(
                start: clip.cmSourceStartTime,
                duration: clip.cmDuration
            )

            // Insert video
            try videoTrack.insertTimeRange(
                sourceTimeRange,
                of: sourceVideoTrack,
                at: clip.cmTimelineStartTime
            )

            // Get source video dimensions and update clip if needed
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

            // Calculate actual video dimensions considering transform (rotation)
            let transformedSize = naturalSize.applying(preferredTransform)
            let actualWidth = abs(transformedSize.width)
            let actualHeight = abs(transformedSize.height)

            // Update clip's source size if not already set
            if clip.sourceWidth == 0 || clip.sourceHeight == 0 {
                await MainActor.run {
                    clip.sourceWidth = Int(actualWidth)
                    clip.sourceHeight = Int(actualHeight)
                }
            }

            // Insert audio if available
            if let audioTrack = audioTrack {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let sourceAudioTrack = audioTracks.first {
                    try audioTrack.insertTimeRange(
                        sourceTimeRange,
                        of: sourceAudioTrack,
                        at: clip.cmTimelineStartTime
                    )
                }
            }

            // Return clip info for video composition building
            let timelineRange = CMTimeRange(
                start: clip.cmTimelineStartTime,
                duration: clip.cmDuration
            )

            return ClipTrackInfo(
                clip: clip,
                trackID: trackID,
                timeRange: timelineRange,
                transition: clip.outTransition
            )

        } catch {
            print("Failed to add clip to composition: \(error)")
            return nil
        }
    }

    private func addAudioClipToTrack(
        clip: AudioClip,
        audioTrack: AVMutableCompositionTrack
    ) async {
        guard let assetURL = clip.assetURL else { return }

        let asset = AVURLAsset(url: assetURL)

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceAudioTrack = audioTracks.first else { return }

            let sourceTimeRange = CMTimeRange(
                start: clip.cmSourceStartTime,
                duration: clip.cmDuration
            )

            try audioTrack.insertTimeRange(
                sourceTimeRange,
                of: sourceAudioTrack,
                at: clip.cmTimelineStartTime
            )
        } catch {
            print("Failed to add audio clip to composition: \(error)")
        }
    }

    /// Create video composition with layer instructions for transforms and transitions
    private func buildVideoComposition(
        for composition: AVMutableComposition,
        clipInfos: [ClipTrackInfo],
        renderSize: CGSize
    ) -> AVMutableVideoComposition? {
        guard !clipInfos.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Group clips by their timeline position to create instructions
        // Sort by start time
        let sortedClips = clipInfos.sorted { $0.timeRange.start < $1.timeRange.start }

        var instructions: [AVMutableVideoCompositionInstruction] = []

        // Create instructions for each clip, handling transitions
        for (index, clipInfo) in sortedClips.enumerated() {
            let instruction = AVMutableVideoCompositionInstruction()

            // Find the video track in the composition
            guard let track = composition.track(withTrackID: clipInfo.trackID) else {
                continue
            }

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

            // Calculate and apply the transform for this clip
            let transform = clipInfo.clip.calculateTransform(for: renderSize)

            // Check if there's a transition from this clip
            if let transition = clipInfo.transition,
               index + 1 < sortedClips.count {
                let nextClipInfo = sortedClips[index + 1]
                let transitionDuration = transition.cmDuration

                // Calculate the transition time range
                let transitionStart = CMTimeSubtract(clipInfo.timeRange.end, transitionDuration)

                // Create instruction for the main clip portion (before transition)
                let mainClipDuration = CMTimeSubtract(clipInfo.timeRange.duration, transitionDuration)
                let mainClipRange = CMTimeRange(start: clipInfo.timeRange.start, duration: mainClipDuration)

                if CMTimeCompare(mainClipDuration, .zero) > 0 {
                    let mainInstruction = AVMutableVideoCompositionInstruction()
                    mainInstruction.timeRange = mainClipRange

                    let mainLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                    mainLayerInstruction.setTransform(transform, at: mainClipRange.start)
                    mainInstruction.layerInstructions = [mainLayerInstruction]
                    instructions.append(mainInstruction)
                }

                // Create transition instruction
                let transitionRange = CMTimeRange(start: transitionStart, duration: transitionDuration)
                let transitionInstruction = AVMutableVideoCompositionInstruction()
                transitionInstruction.timeRange = transitionRange

                // Apply transition effect based on type
                let fromLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                fromLayerInstruction.setTransform(transform, at: transitionStart)

                // Apply transition effect to the from clip
                applyTransitionEffect(
                    transition: transition,
                    toInstruction: fromLayerInstruction,
                    startTime: transitionStart,
                    duration: transitionDuration,
                    renderSize: renderSize,
                    isFromClip: true
                )

                var layerInstructions = [fromLayerInstruction]

                // If the next clip overlaps with the transition, include it
                if let nextTrack = composition.track(withTrackID: nextClipInfo.trackID) {
                    let nextTransform = nextClipInfo.clip.calculateTransform(for: renderSize)
                    let toLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: nextTrack)
                    toLayerInstruction.setTransform(nextTransform, at: transitionStart)

                    applyTransitionEffect(
                        transition: transition,
                        toInstruction: toLayerInstruction,
                        startTime: transitionStart,
                        duration: transitionDuration,
                        renderSize: renderSize,
                        isFromClip: false
                    )

                    layerInstructions.append(toLayerInstruction)
                }

                transitionInstruction.layerInstructions = layerInstructions
                instructions.append(transitionInstruction)

            } else {
                // No transition - normal clip instruction
                instruction.timeRange = clipInfo.timeRange
                layerInstruction.setTransform(transform, at: clipInfo.timeRange.start)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
            }
        }

        // Sort instructions by start time to ensure proper order
        instructions.sort { $0.timeRange.start < $1.timeRange.start }

        videoComposition.instructions = instructions

        return videoComposition
    }

    /// Apply transition effect to a layer instruction
    private func applyTransitionEffect(
        transition: Transition,
        toInstruction: AVMutableVideoCompositionLayerInstruction,
        startTime: CMTime,
        duration: CMTime,
        renderSize: CGSize,
        isFromClip: Bool
    ) {
        let endTime = CMTimeAdd(startTime, duration)

        switch transition.type {
        case .crossDissolve:
            // Cross dissolve: fade out the from clip, fade in the to clip
            if isFromClip {
                toInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                toInstruction.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: CMTimeRange(start: startTime, duration: duration))
            }

        case .fadeToBlack:
            // Fade to black then show next
            if isFromClip {
                toInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                // To clip stays at 0 during fade out, then snaps to visible
                toInstruction.setOpacity(0.0, at: startTime)
                toInstruction.setOpacity(1.0, at: endTime)
            }

        case .fadeFromBlack:
            // Show from clip then fade in next
            if isFromClip {
                toInstruction.setOpacity(1.0, at: startTime)
                toInstruction.setOpacity(0.0, at: endTime)
            } else {
                toInstruction.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: CMTimeRange(start: startTime, duration: duration))
            }

        case .slideLeft:
            // Next clip slides in from the right
            if isFromClip {
                // From clip slides out to the left
                let startTransform = CGAffineTransform.identity
                let endTransform = CGAffineTransform(translationX: -renderSize.width, y: 0)
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                // To clip slides in from the right
                let startTransform = CGAffineTransform(translationX: renderSize.width, y: 0)
                let endTransform = CGAffineTransform.identity
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            }

        case .slideRight:
            // Next clip slides in from the left
            if isFromClip {
                let startTransform = CGAffineTransform.identity
                let endTransform = CGAffineTransform(translationX: renderSize.width, y: 0)
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                let startTransform = CGAffineTransform(translationX: -renderSize.width, y: 0)
                let endTransform = CGAffineTransform.identity
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            }

        case .slideUp:
            // Next clip slides in from the bottom
            if isFromClip {
                let startTransform = CGAffineTransform.identity
                let endTransform = CGAffineTransform(translationX: 0, y: -renderSize.height)
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                let startTransform = CGAffineTransform(translationX: 0, y: renderSize.height)
                let endTransform = CGAffineTransform.identity
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            }

        case .slideDown:
            // Next clip slides in from the top
            if isFromClip {
                let startTransform = CGAffineTransform.identity
                let endTransform = CGAffineTransform(translationX: 0, y: renderSize.height)
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                let startTransform = CGAffineTransform(translationX: 0, y: -renderSize.height)
                let endTransform = CGAffineTransform.identity
                toInstruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: CMTimeRange(start: startTime, duration: duration))
            }

        case .wipeLeft, .wipeRight:
            // Wipe transitions are more complex - use simple crossfade as fallback
            // For a true wipe, you'd need a custom compositor
            if isFromClip {
                toInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: CMTimeRange(start: startTime, duration: duration))
            } else {
                toInstruction.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: CMTimeRange(start: startTime, duration: duration))
            }
        }
    }
}
