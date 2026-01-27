//
//  CompositionEngine.swift
//  Videographics
//

import Foundation
import AVFoundation
import CoreMedia
import UIKit
import QuartzCore

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
    /// Default render size is 1080x1920 (portrait 9:16)
    func buildComposition(from timeline: Timeline, renderSize: CGSize = CGSize(width: 1080, height: 1920)) async -> CompositionResult? {
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

        // Build video composition with transforms and overlays
        let videoComposition = buildVideoComposition(
            for: composition,
            clipInfos: clipInfos,
            renderSize: renderSize,
            timeline: timeline
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
        renderSize: CGSize,
        timeline: Timeline
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

        // Fill gaps with black instructions to prevent raw video showing
        let timelineDuration = timeline.duration
        instructions = fillGapsWithBlackInstructions(
            instructions: instructions,
            timelineDuration: timelineDuration
        )

        videoComposition.instructions = instructions

        // Add text and graphics overlays using Core Animation
        let animationTool = buildOverlayLayers(
            timeline: timeline,
            renderSize: renderSize,
            duration: timelineDuration
        )
        if let tool = animationTool {
            videoComposition.animationTool = tool
        }

        return videoComposition
    }

    // MARK: - Text and Graphics Overlays

    /// Build overlay layers for text, graphics, and infographics
    private func buildOverlayLayers(
        timeline: Timeline,
        renderSize: CGSize,
        duration: CMTime
    ) -> AVVideoCompositionCoreAnimationTool? {
        let hasTextOverlays = timeline.textLayers.contains { !$0.clips.isEmpty && $0.isVisible }
        let hasGraphicsOverlays = timeline.graphicsLayers.contains { !$0.clips.isEmpty && $0.isVisible }
        let hasInfographicOverlays = timeline.infographicLayers.contains { !$0.clips.isEmpty && $0.isVisible }

        guard hasTextOverlays || hasGraphicsOverlays || hasInfographicOverlays else { return nil }

        // Parent layer that contains everything
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)

        // Video layer where video will be rendered
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Add text layers (higher zIndex = on top)
        let sortedTextLayers = timeline.textLayers
            .filter { $0.isVisible }
            .sorted { $0.zIndex < $1.zIndex }

        for textLayer in sortedTextLayers {
            for clip in textLayer.sortedClips {
                if let layer = createTextLayer(from: clip, renderSize: renderSize, duration: duration) {
                    parentLayer.addSublayer(layer)
                }
            }
        }

        // Add graphics layers
        let sortedGraphicsLayers = timeline.graphicsLayers
            .filter { $0.isVisible }
            .sorted { $0.zIndex < $1.zIndex }

        for graphicsLayer in sortedGraphicsLayers {
            for clip in graphicsLayer.sortedClips {
                if let layer = createGraphicsLayer(from: clip, renderSize: renderSize, duration: duration) {
                    parentLayer.addSublayer(layer)
                }
            }
        }

        // Add infographic layers
        let sortedInfographicLayers = timeline.infographicLayers
            .filter { $0.isVisible }
            .sorted { $0.zIndex < $1.zIndex }

        for infographicLayer in sortedInfographicLayers {
            for clip in infographicLayer.sortedClips {
                if let layer = createInfographicLayer(from: clip, renderSize: renderSize, duration: duration) {
                    parentLayer.addSublayer(layer)
                }
            }
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    /// Create a CATextLayer for a text clip
    private nonisolated func createTextLayer(
        from clip: TextClip,
        renderSize: CGSize,
        duration: CMTime
    ) -> CALayer? {
        let textLayer = CATextLayer()

        // Capture clip properties
        let text = clip.text
        let fontName = clip.fontName
        let fontSize = clip.fontSize
        let clipScale = clip.scale
        let textColorHex = clip.textColorHex
        let backgroundColorHex = clip.backgroundColorHex
        let alignment = clip.alignment
        let positionX = clip.positionX
        let positionY = clip.positionY
        let rotation = clip.rotation
        let startTime = clip.cmTimelineStartTime
        let endTime = clip.cmTimelineEndTime

        // Set text content and styling
        textLayer.string = text
        textLayer.font = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)
        textLayer.fontSize = CGFloat(fontSize) * CGFloat(clipScale)
        textLayer.foregroundColor = colorFromHex(textColorHex) ?? UIColor.white.cgColor

        // Background color
        if let bgHex = backgroundColorHex {
            textLayer.backgroundColor = colorFromHex(bgHex)
        }

        // Alignment
        switch alignment {
        case .left:
            textLayer.alignmentMode = .left
        case .center:
            textLayer.alignmentMode = .center
        case .right:
            textLayer.alignmentMode = .right
        }

        textLayer.isWrapped = true
        textLayer.truncationMode = .none
        textLayer.contentsScale = 2.0 // Use fixed scale for nonisolated context

        // Calculate size based on text
        let maxWidth = renderSize.width * 0.9
        let textSize = calculateTextSize(
            text: text,
            fontName: fontName,
            fontSize: CGFloat(fontSize) * CGFloat(clipScale),
            maxWidth: maxWidth
        )

        textLayer.bounds = CGRect(origin: .zero, size: textSize)

        // Position (convert from normalized -1 to 1 to actual coordinates)
        // In Core Animation, origin is bottom-left
        let centerX = renderSize.width / 2 + CGFloat(positionX) * (renderSize.width / 2)
        let centerY = renderSize.height / 2 + CGFloat(positionY) * (renderSize.height / 2)
        textLayer.position = CGPoint(x: centerX, y: centerY)

        // Rotation
        if rotation != 0 {
            textLayer.transform = CATransform3DMakeRotation(CGFloat(rotation) * .pi / 180, 0, 0, 1)
        }

        // Animate visibility (show/hide based on clip timing)
        addVisibilityAnimation(
            to: textLayer,
            startTime: startTime,
            endTime: endTime,
            duration: duration
        )

        return textLayer
    }

    /// Create a CALayer for a graphics clip
    private func createGraphicsLayer(
        from clip: GraphicsClip,
        renderSize: CGSize,
        duration: CMTime
    ) -> CALayer? {
        // Load image from data or URL
        var image: UIImage?

        if let imageData = clip.imageData {
            image = UIImage(data: imageData)
        } else if let imageURL = clip.imageURL,
                  let data = try? Data(contentsOf: imageURL) {
            image = UIImage(data: data)
        }

        guard let cgImage = image?.cgImage else { return nil }

        let imageLayer = CALayer()
        imageLayer.contents = cgImage
        imageLayer.contentsGravity = .resizeAspect

        // Calculate size
        let imageSize = CGSize(
            width: CGFloat(clip.sourceWidth) * CGFloat(clip.scale),
            height: CGFloat(clip.sourceHeight) * CGFloat(clip.scale)
        )
        imageLayer.bounds = CGRect(origin: .zero, size: imageSize)

        // Position (convert from normalized -1 to 1 to actual coordinates)
        let centerX = renderSize.width / 2 + CGFloat(clip.positionX) * (renderSize.width / 2)
        let centerY = renderSize.height / 2 + CGFloat(clip.positionY) * (renderSize.height / 2)
        imageLayer.position = CGPoint(x: centerX, y: centerY)

        // Rotation and opacity
        var transform = CATransform3DIdentity
        if clip.rotation != 0 {
            transform = CATransform3DRotate(transform, CGFloat(clip.rotation) * .pi / 180, 0, 0, 1)
        }
        imageLayer.transform = transform
        imageLayer.opacity = clip.opacity

        // Animate visibility
        addVisibilityAnimation(
            to: imageLayer,
            startTime: clip.cmTimelineStartTime,
            endTime: clip.cmTimelineEndTime,
            duration: duration
        )

        return imageLayer
    }

    /// Create a CALayer for an infographic clip
    private nonisolated func createInfographicLayer(
        from clip: InfographicClip,
        renderSize: CGSize,
        duration: CMTime
    ) -> CALayer? {
        guard let chartData = clip.chartData else { return nil }

        // Render the chart to an image on main thread
        let chartSize = CGSize(
            width: renderSize.width * 0.8,
            height: renderSize.height * 0.4
        )

        // Capture clip properties for main thread
        let chartType = clip.chartType
        let stylePreset = clip.stylePreset
        let clipScale = clip.scale
        let positionX = clip.positionX
        let positionY = clip.positionY
        let rotation = clip.rotation
        let opacity = clip.opacity
        let startTime = clip.cmTimelineStartTime
        let endTime = clip.cmTimelineEndTime

        var chartImage: UIImage?

        // Render chart on main thread synchronously
        if Thread.isMainThread {
            chartImage = MainActor.assumeIsolated {
                ChartRenderer.shared.renderChart(
                    data: chartData,
                    chartType: chartType,
                    style: stylePreset,
                    size: chartSize
                )
            }
        } else {
            DispatchQueue.main.sync {
                chartImage = MainActor.assumeIsolated {
                    ChartRenderer.shared.renderChart(
                        data: chartData,
                        chartType: chartType,
                        style: stylePreset,
                        size: chartSize
                    )
                }
            }
        }

        guard let image = chartImage, let cgImage = image.cgImage else { return nil }

        let imageLayer = CALayer()
        imageLayer.contents = cgImage
        imageLayer.contentsGravity = .resizeAspect

        // Calculate size with scale
        let scaledSize = CGSize(
            width: chartSize.width * CGFloat(clipScale),
            height: chartSize.height * CGFloat(clipScale)
        )
        imageLayer.bounds = CGRect(origin: .zero, size: scaledSize)

        // Position (convert from normalized -1 to 1 to actual coordinates)
        let centerX = renderSize.width / 2 + CGFloat(positionX) * (renderSize.width / 2)
        let centerY = renderSize.height / 2 + CGFloat(positionY) * (renderSize.height / 2)
        imageLayer.position = CGPoint(x: centerX, y: centerY)

        // Rotation and opacity
        var transform = CATransform3DIdentity
        if rotation != 0 {
            transform = CATransform3DRotate(transform, CGFloat(rotation) * .pi / 180, 0, 0, 1)
        }
        imageLayer.transform = transform
        imageLayer.opacity = opacity

        // Animate visibility
        addVisibilityAnimation(
            to: imageLayer,
            startTime: startTime,
            endTime: endTime,
            duration: duration
        )

        return imageLayer
    }

    /// Add visibility animation to show layer only during clip duration
    private nonisolated func addVisibilityAnimation(
        to layer: CALayer,
        startTime: CMTime,
        endTime: CMTime,
        duration: CMTime
    ) {
        let startSeconds = CMTimeGetSeconds(startTime)
        let endSeconds = CMTimeGetSeconds(endTime)
        let totalSeconds = CMTimeGetSeconds(duration)

        // Initially hidden
        layer.opacity = 0

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.calculationMode = .discrete
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = totalSeconds

        // Build keyframe times and values
        var times: [NSNumber] = []
        var values: [NSNumber] = []

        // Before start: hidden
        if startSeconds > 0 {
            times.append(0)
            values.append(0)
        }

        // At start: visible
        times.append(NSNumber(value: startSeconds / totalSeconds))
        values.append(1)

        // At end: hidden
        times.append(NSNumber(value: endSeconds / totalSeconds))
        values.append(0)

        animation.keyTimes = times
        animation.values = values

        layer.add(animation, forKey: "visibilityAnimation")
    }

    /// Convert hex string to CGColor (nonisolated for use in overlay creation)
    private nonisolated func colorFromHex(_ hex: String) -> CGColor? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            return CGColor(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if length == 8 {
            return CGColor(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }

    /// Calculate the size needed for text
    private nonisolated func calculateTextSize(text: String, fontName: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        // Add some padding
        return CGSize(
            width: ceil(boundingRect.width) + 20,
            height: ceil(boundingRect.height) + 10
        )
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

    /// Fill gaps in the instruction list with black (empty) instructions
    /// This prevents raw video tracks from showing when there's no clip
    private func fillGapsWithBlackInstructions(
        instructions: [AVMutableVideoCompositionInstruction],
        timelineDuration: CMTime
    ) -> [AVMutableVideoCompositionInstruction] {
        guard !instructions.isEmpty else {
            // No clips - create single black instruction for entire duration
            let blackInstruction = AVMutableVideoCompositionInstruction()
            blackInstruction.timeRange = CMTimeRange(start: .zero, duration: timelineDuration)
            blackInstruction.backgroundColor = CGColor(gray: 0, alpha: 1) // Black
            blackInstruction.layerInstructions = []
            return [blackInstruction]
        }

        var result: [AVMutableVideoCompositionInstruction] = []
        var currentTime = CMTime.zero

        // Sort instructions by start time
        let sortedInstructions = instructions.sorted { $0.timeRange.start < $1.timeRange.start }

        for instruction in sortedInstructions {
            // Check for gap before this instruction
            if CMTimeCompare(currentTime, instruction.timeRange.start) < 0 {
                // There's a gap - fill with black
                let gapDuration = CMTimeSubtract(instruction.timeRange.start, currentTime)
                let blackInstruction = AVMutableVideoCompositionInstruction()
                blackInstruction.timeRange = CMTimeRange(start: currentTime, duration: gapDuration)
                blackInstruction.backgroundColor = CGColor(gray: 0, alpha: 1) // Black
                blackInstruction.layerInstructions = []
                result.append(blackInstruction)
            }

            result.append(instruction)
            currentTime = instruction.timeRange.end
        }

        // Check for gap after the last instruction until timeline end
        if CMTimeCompare(currentTime, timelineDuration) < 0 {
            let gapDuration = CMTimeSubtract(timelineDuration, currentTime)
            let blackInstruction = AVMutableVideoCompositionInstruction()
            blackInstruction.timeRange = CMTimeRange(start: currentTime, duration: gapDuration)
            blackInstruction.backgroundColor = CGColor(gray: 0, alpha: 1) // Black
            blackInstruction.layerInstructions = []
            result.append(blackInstruction)
        }

        return result
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    /// Initialize UIColor from hex string (nonisolated for use in actor contexts)
    @MainActor
    static func fromHex(_ hex: String) -> UIColor? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            return UIColor(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if length == 8 {
            return UIColor(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }

    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            self.init(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if length == 8 {
            self.init(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }
}
