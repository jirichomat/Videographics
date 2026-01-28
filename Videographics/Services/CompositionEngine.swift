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
    /// - Parameter forExport: When true, includes Core Animation overlays (text, captions). Must be false for AVPlayerItem preview.
    func buildComposition(from timeline: Timeline, renderSize: CGSize = CGSize(width: 1080, height: 1920), forExport: Bool = false) async -> CompositionResult? {
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
            timeline: timeline,
            forExport: forExport
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

            // Load actual asset duration to validate source time range
            let assetDuration = try await asset.load(.duration)

            // Validate and clamp source time range to asset bounds
            var validatedSourceStart = clip.cmSourceStartTime
            var validatedDuration = clip.cmDuration

            // If sourceStartTime is beyond asset duration, this clip is invalid
            if CMTimeCompare(validatedSourceStart, assetDuration) >= 0 {
                print("Invalid clip: sourceStartTime (\(validatedSourceStart.seconds)s) >= assetDuration (\(assetDuration.seconds)s)")
                // Reset to start of asset with original clip duration clamped
                validatedSourceStart = .zero
                validatedDuration = CMTimeMinimum(clip.cmDuration, assetDuration)
            }

            // Clamp duration if sourceStart + duration exceeds asset duration
            let maxDuration = CMTimeSubtract(assetDuration, validatedSourceStart)
            if CMTimeCompare(validatedDuration, maxDuration) > 0 {
                print("Clamping clip duration from \(validatedDuration.seconds)s to \(maxDuration.seconds)s")
                validatedDuration = maxDuration
            }

            // Ensure we have a valid duration
            if CMTimeCompare(validatedDuration, .zero) <= 0 {
                print("Invalid clip: zero or negative duration after clamping")
                return nil
            }

            // Define the time range from the source
            let sourceTimeRange = CMTimeRange(
                start: validatedSourceStart,
                duration: validatedDuration
            )

            // Insert video
            try videoTrack.insertTimeRange(
                sourceTimeRange,
                of: sourceVideoTrack,
                at: clip.cmTimelineStartTime
            )

            // Get source video dimensions and preferred transform
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

            // Calculate actual video dimensions considering transform (rotation)
            let transformedSize = naturalSize.applying(preferredTransform)
            let actualWidth = abs(transformedSize.width)
            let actualHeight = abs(transformedSize.height)

            // Always update clip's transform and source size to ensure they're correct
            // This handles cases where the clip was created before we had this data
            await MainActor.run {
                // Store the preferred transform for use during composition
                clip.preferredTransform = preferredTransform

                // Store the TRANSFORMED (post-rotation) dimensions
                // This represents what the video looks like after applying preferredTransform
                clip.sourceWidth = Int(actualWidth)
                clip.sourceHeight = Int(actualHeight)

                print("[TRANSFORM] Clip \(clip.id.uuidString.prefix(8)): naturalSize=\(naturalSize), preferredTransform=\(preferredTransform), finalSize=\(actualWidth)x\(actualHeight)")
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
            // Use validatedDuration to match what was actually inserted
            let timelineRange = CMTimeRange(
                start: clip.cmTimelineStartTime,
                duration: validatedDuration
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
    /// - Parameter forExport: When true, includes Core Animation overlays. Must be false for AVPlayerItem.
    private func buildVideoComposition(
        for composition: AVMutableComposition,
        clipInfos: [ClipTrackInfo],
        renderSize: CGSize,
        timeline: Timeline,
        forExport: Bool
    ) -> AVMutableVideoComposition? {
        guard !clipInfos.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Build non-overlapping instructions that handle multiple layers
        let instructions = buildMergedInstructions(
            for: composition,
            clipInfos: clipInfos,
            renderSize: renderSize
        )

        // Fill gaps with black instructions to prevent raw video showing
        let timelineDuration = timeline.duration
        let finalInstructions = fillGapsWithBlackInstructions(
            instructions: instructions,
            timelineDuration: timelineDuration
        )

        videoComposition.instructions = finalInstructions

        // Add text and graphics overlays using Core Animation (export only)
        // AVVideoCompositionCoreAnimationTool cannot be used with AVPlayerItem for preview
        if forExport {
            let animationTool = buildOverlayLayers(
                timeline: timeline,
                renderSize: renderSize,
                duration: timelineDuration
            )
            if let tool = animationTool {
                videoComposition.animationTool = tool
            }
        }

        return videoComposition
    }

    /// Build merged instructions that handle overlapping clips from different layers
    private func buildMergedInstructions(
        for composition: AVMutableComposition,
        clipInfos: [ClipTrackInfo],
        renderSize: CGSize
    ) -> [AVMutableVideoCompositionInstruction] {
        guard !clipInfos.isEmpty else { return [] }

        // Collect all unique time points where visibility changes
        var timePoints = Set<CMTime>()
        for clipInfo in clipInfos {
            timePoints.insert(clipInfo.timeRange.start)
            timePoints.insert(clipInfo.timeRange.end)
        }

        // Sort time points
        let sortedTimePoints = timePoints.sorted { CMTimeCompare($0, $1) < 0 }

        var instructions: [AVMutableVideoCompositionInstruction] = []

        // Create an instruction for each segment between time points
        for i in 0..<(sortedTimePoints.count - 1) {
            let segmentStart = sortedTimePoints[i]
            let segmentEnd = sortedTimePoints[i + 1]
            let segmentDuration = CMTimeSubtract(segmentEnd, segmentStart)

            // Skip zero-duration segments
            if CMTimeCompare(segmentDuration, .zero) <= 0 {
                continue
            }

            let segmentRange = CMTimeRange(start: segmentStart, duration: segmentDuration)

            // Find all clips visible during this segment
            var visibleClips: [ClipTrackInfo] = []
            for clipInfo in clipInfos {
                // Clip is visible if its time range contains this segment
                let clipStart = clipInfo.timeRange.start
                let clipEnd = clipInfo.timeRange.end

                // Check if segment is within clip's time range
                if CMTimeCompare(segmentStart, clipStart) >= 0 &&
                   CMTimeCompare(segmentEnd, clipEnd) <= 0 {
                    visibleClips.append(clipInfo)
                }
            }

            // Skip segments with no visible clips (will be filled with black later)
            if visibleClips.isEmpty {
                continue
            }

            // Sort by track ID (higher zIndex = higher track ID = rendered on top)
            // Layer instructions are applied in reverse order, so lower index = on top
            visibleClips.sort { $0.trackID > $1.trackID }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segmentRange

            var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

            for clipInfo in visibleClips {
                guard let track = composition.track(withTrackID: clipInfo.trackID) else {
                    continue
                }

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                let transform = clipInfo.clip.calculateTransform(for: renderSize)
                layerInstruction.setTransform(transform, at: segmentStart)
                layerInstructions.append(layerInstruction)

                print("[COMPOSITION] Segment \(i): clip=\(clipInfo.clip.id.uuidString.prefix(8)), trackID=\(clipInfo.trackID)")
                print("[COMPOSITION]   sourceSize=\(clipInfo.clip.sourceWidth)x\(clipInfo.clip.sourceHeight)")
                print("[COMPOSITION]   prefTransform=[\(clipInfo.clip.preferredTransformA), \(clipInfo.clip.preferredTransformB), \(clipInfo.clip.preferredTransformC), \(clipInfo.clip.preferredTransformD)]")
                print("[COMPOSITION]   finalTransform=[a=\(transform.a), b=\(transform.b), c=\(transform.c), d=\(transform.d), tx=\(transform.tx), ty=\(transform.ty)]")
            }

            instruction.layerInstructions = layerInstructions
            instructions.append(instruction)
        }

        return instructions
    }

    // MARK: - Text and Graphics Overlays

    /// Build overlay layers for text, graphics, infographics, and captions
    private func buildOverlayLayers(
        timeline: Timeline,
        renderSize: CGSize,
        duration: CMTime
    ) -> AVVideoCompositionCoreAnimationTool? {
        let hasTextOverlays = timeline.textLayers.contains { !$0.clips.isEmpty && $0.isVisible }
        let hasGraphicsOverlays = timeline.graphicsLayers.contains { !$0.clips.isEmpty && $0.isVisible }
        let hasInfographicOverlays = timeline.infographicLayers.contains { !$0.clips.isEmpty && $0.isVisible }
        let hasCaptionOverlays = timeline.captionLayers.contains { !$0.clips.isEmpty && $0.isVisible }

        print("[OVERLAY] Building overlays - text:\(hasTextOverlays) graphics:\(hasGraphicsOverlays) infographic:\(hasInfographicOverlays) captions:\(hasCaptionOverlays)")

        guard hasTextOverlays || hasGraphicsOverlays || hasInfographicOverlays || hasCaptionOverlays else { return nil }

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

        // Add caption layers
        let sortedCaptionLayers = timeline.captionLayers
            .filter { $0.isVisible }
            .sorted { $0.zIndex < $1.zIndex }

        print("[OVERLAY] Processing \(sortedCaptionLayers.count) visible caption layers")
        for captionLayer in sortedCaptionLayers {
            print("[OVERLAY] Caption layer has \(captionLayer.clips.count) clips")
            for clip in captionLayer.sortedClips {
                print("[OVERLAY] Creating caption layers for clip with \(clip.words.count) words, start=\(clip.cmTimelineStartTime.seconds)s")
                let layers = createCaptionLayers(from: clip, renderSize: renderSize, duration: duration)
                print("[OVERLAY] Created \(layers.count) caption CALayers")
                for layer in layers {
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

    /// Create CALayers for a caption clip
    /// Returns multiple layers for word-by-word animation styles
    private nonisolated func createCaptionLayers(
        from clip: CaptionClip,
        renderSize: CGSize,
        duration: CMTime
    ) -> [CALayer] {
        let words = clip.words
        guard !words.isEmpty else { return [] }

        // Route premium styles to the premium renderer
        let style = clip.style
        if style.usesPremiumRenderer {
            return createPremiumCaptionLayers(from: clip, renderSize: renderSize, duration: duration)
        }

        // Capture clip properties
        let fontName = clip.fontName
        let fontSize = clip.fontSize
        let clipScale = clip.scale
        let textColorHex = clip.textColorHex
        let highlightColorHex = clip.highlightColorHex
        let backgroundColorHex = clip.backgroundColorHex
        let positionX = clip.positionX
        let positionY = clip.positionY
        let maxWordsPerLine = clip.maxWordsPerLine
        let showBackground = clip.showBackground
        let clipStartTime = clip.cmTimelineStartTime
        let clipEndTime = clip.cmTimelineEndTime

        // Group words into lines
        let lines = groupWordsIntoLines(words, maxPerLine: maxWordsPerLine)

        // For animated styles (TikTok, Karaoke), create separate layers for each word segment
        if style.hasWordAnimation {
            return createAnimatedCaptionLayers(
                words: words,
                lines: lines,
                fontName: fontName,
                fontSize: fontSize,
                scale: clipScale,
                textColorHex: textColorHex,
                highlightColorHex: highlightColorHex,
                backgroundColorHex: backgroundColorHex,
                positionX: positionX,
                positionY: positionY,
                showBackground: showBackground,
                clipStartTime: clipStartTime,
                clipEndTime: clipEndTime,
                renderSize: renderSize,
                totalDuration: duration,
                style: style
            )
        } else {
            // For static styles, create simple text layers for each line
            return createStaticCaptionLayers(
                lines: lines,
                fontName: fontName,
                fontSize: fontSize,
                scale: clipScale,
                textColorHex: textColorHex,
                backgroundColorHex: backgroundColorHex,
                positionX: positionX,
                positionY: positionY,
                showBackground: showBackground,
                clipStartTime: clipStartTime,
                clipEndTime: clipEndTime,
                renderSize: renderSize,
                totalDuration: duration
            )
        }
    }

    /// Group words into lines for display
    private nonisolated func groupWordsIntoLines(_ words: [CaptionWord], maxPerLine: Int) -> [[CaptionWord]] {
        var lines: [[CaptionWord]] = []
        var currentLine: [CaptionWord] = []

        for word in words {
            currentLine.append(word)
            if currentLine.count >= maxPerLine {
                lines.append(currentLine)
                currentLine = []
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    /// Create static caption layers (Classic, Minimal, Bold, Outline styles)
    private nonisolated func createStaticCaptionLayers(
        lines: [[CaptionWord]],
        fontName: String,
        fontSize: Float,
        scale: Float,
        textColorHex: String,
        backgroundColorHex: String?,
        positionX: Float,
        positionY: Float,
        showBackground: Bool,
        clipStartTime: CMTime,
        clipEndTime: CMTime,
        renderSize: CGSize,
        totalDuration: CMTime
    ) -> [CALayer] {
        var layers: [CALayer] = []

        for (lineIndex, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }

            // Calculate timing for this line
            let lineStartSeconds = line.first?.startTimeSeconds ?? 0
            let lineEndSeconds = line.last?.endTimeSeconds ?? 0

            // Create text for this line
            let lineText = line.map { $0.word }.joined(separator: " ")

            // Create container layer for background + text
            let containerLayer = CALayer()
            containerLayer.contentsScale = 2.0

            // Create text layer with attributed string for reliable rendering
            let textLayer = CATextLayer()
            let scaledFontSize = CGFloat(fontSize) * CGFloat(scale)
            let font = UIFont(name: fontName, size: scaledFontSize) ?? UIFont.systemFont(ofSize: scaledFontSize, weight: .semibold)
            let textColor = colorFromHex(textColorHex).flatMap { UIColor(cgColor: $0) } ?? UIColor.white

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributedString = NSAttributedString(
                string: lineText,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
            textLayer.string = attributedString
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true
            textLayer.truncationMode = .none
            textLayer.contentsScale = UIScreen.main.scale

            // Calculate size
            let maxWidth = renderSize.width * 0.9
            let textSize = calculateTextSize(
                text: lineText,
                fontName: fontName,
                fontSize: CGFloat(fontSize) * CGFloat(scale),
                maxWidth: maxWidth
            )

            textLayer.bounds = CGRect(origin: .zero, size: textSize)

            // Position text within container
            let padding: CGFloat = showBackground ? 12 : 0
            let containerSize = CGSize(
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )
            containerLayer.bounds = CGRect(origin: .zero, size: containerSize)
            textLayer.position = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

            // Add background if needed
            if showBackground {
                let bgColor = backgroundColorHex.flatMap { colorFromHex($0) } ?? CGColor(gray: 0, alpha: 0.7)
                containerLayer.backgroundColor = bgColor
                containerLayer.cornerRadius = 6
            }

            containerLayer.addSublayer(textLayer)

            // Position container
            let centerX = renderSize.width / 2 + CGFloat(positionX) * (renderSize.width / 2)
            let lineOffset = CGFloat(lineIndex) * (containerSize.height + 8)
            let centerY = renderSize.height / 2 + CGFloat(positionY) * (renderSize.height / 2) - lineOffset
            containerLayer.position = CGPoint(x: centerX, y: centerY)

            // Calculate absolute times
            let lineStartTime = CMTimeAdd(clipStartTime, CMTime(seconds: lineStartSeconds, preferredTimescale: 600))
            let lineEndTime = CMTimeAdd(clipStartTime, CMTime(seconds: lineEndSeconds, preferredTimescale: 600))

            // Add visibility animation
            addVisibilityAnimation(
                to: containerLayer,
                startTime: lineStartTime,
                endTime: lineEndTime,
                duration: totalDuration
            )

            layers.append(containerLayer)
        }

        return layers
    }

    /// Create animated caption layers (TikTok, Karaoke styles)
    private nonisolated func createAnimatedCaptionLayers(
        words: [CaptionWord],
        lines: [[CaptionWord]],
        fontName: String,
        fontSize: Float,
        scale: Float,
        textColorHex: String,
        highlightColorHex: String,
        backgroundColorHex: String?,
        positionX: Float,
        positionY: Float,
        showBackground: Bool,
        clipStartTime: CMTime,
        clipEndTime: CMTime,
        renderSize: CGSize,
        totalDuration: CMTime,
        style: CaptionStyle
    ) -> [CALayer] {
        var layers: [CALayer] = []

        for (lineIndex, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }

            // Calculate timing for this line
            let lineStartSeconds = line.first?.startTimeSeconds ?? 0
            let lineEndSeconds = line.last?.endTimeSeconds ?? 0
            let lineText = line.map { $0.word }.joined(separator: " ")

            // Create container
            let containerLayer = CALayer()
            containerLayer.contentsScale = 2.0

            // Calculate size for the full line
            let maxWidth = renderSize.width * 0.9
            let textSize = calculateTextSize(
                text: lineText,
                fontName: fontName,
                fontSize: CGFloat(fontSize) * CGFloat(scale),
                maxWidth: maxWidth
            )

            let padding: CGFloat = showBackground ? 12 : 0
            let containerSize = CGSize(
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )
            containerLayer.bounds = CGRect(origin: .zero, size: containerSize)

            // Add background if needed
            if showBackground {
                let bgColor = backgroundColorHex.flatMap { colorFromHex($0) } ?? CGColor(gray: 0, alpha: 0.7)
                containerLayer.backgroundColor = bgColor
                containerLayer.cornerRadius = 6
            }

            // Create base text layer with attributed string (unhighlighted)
            let scaledFontSize = CGFloat(fontSize) * CGFloat(scale)
            let font = UIFont(name: fontName, size: scaledFontSize) ?? UIFont.systemFont(ofSize: scaledFontSize, weight: .semibold)
            let baseTextColor = colorFromHex(textColorHex).flatMap { UIColor(cgColor: $0) } ?? UIColor.white

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let baseTextLayer = CATextLayer()
            let baseAttributedString = NSAttributedString(
                string: lineText,
                attributes: [
                    .font: font,
                    .foregroundColor: baseTextColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
            baseTextLayer.string = baseAttributedString
            baseTextLayer.alignmentMode = .center
            baseTextLayer.isWrapped = true
            baseTextLayer.truncationMode = .none
            baseTextLayer.contentsScale = UIScreen.main.scale
            baseTextLayer.bounds = CGRect(origin: .zero, size: textSize)
            baseTextLayer.position = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
            containerLayer.addSublayer(baseTextLayer)

            // For TikTok/Karaoke style, add animated highlight overlay
            // This creates a word-by-word highlight effect
            if style == .tiktok || style == .karaoke {
                // Create highlight layer that will be revealed word by word
                let highlightTextColor = colorFromHex(highlightColorHex).flatMap { UIColor(cgColor: $0) } ?? UIColor.yellow
                let highlightAttributedString = NSAttributedString(
                    string: lineText,
                    attributes: [
                        .font: font,
                        .foregroundColor: highlightTextColor,
                        .paragraphStyle: paragraphStyle
                    ]
                )

                let highlightLayer = CATextLayer()
                highlightLayer.string = highlightAttributedString
                highlightLayer.alignmentMode = .center
                highlightLayer.isWrapped = true
                highlightLayer.truncationMode = .none
                highlightLayer.contentsScale = UIScreen.main.scale
                highlightLayer.bounds = CGRect(origin: .zero, size: textSize)
                highlightLayer.position = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

                // Add mask animation to reveal words progressively
                addWordRevealAnimation(
                    to: highlightLayer,
                    words: line,
                    lineText: lineText,
                    clipStartTime: clipStartTime,
                    totalDuration: totalDuration,
                    layerSize: textSize
                )

                containerLayer.addSublayer(highlightLayer)
            }

            // Position container
            let centerX = renderSize.width / 2 + CGFloat(positionX) * (renderSize.width / 2)
            let lineOffset = CGFloat(lineIndex) * (containerSize.height + 8)
            let centerY = renderSize.height / 2 + CGFloat(positionY) * (renderSize.height / 2) - lineOffset
            containerLayer.position = CGPoint(x: centerX, y: centerY)

            // Calculate absolute times for visibility
            let lineStartTime = CMTimeAdd(clipStartTime, CMTime(seconds: lineStartSeconds, preferredTimescale: 600))
            let lineEndTime = CMTimeAdd(clipStartTime, CMTime(seconds: lineEndSeconds, preferredTimescale: 600))

            // Add visibility animation
            addVisibilityAnimation(
                to: containerLayer,
                startTime: lineStartTime,
                endTime: lineEndTime,
                duration: totalDuration
            )

            layers.append(containerLayer)
        }

        return layers
    }

    /// Add word reveal animation using mask
    private nonisolated func addWordRevealAnimation(
        to layer: CATextLayer,
        words: [CaptionWord],
        lineText: String,
        clipStartTime: CMTime,
        totalDuration: CMTime,
        layerSize: CGSize
    ) {
        guard !words.isEmpty else { return }

        // Create mask layer that will be animated
        let maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.white.cgColor
        maskLayer.frame = CGRect(x: 0, y: 0, width: 0, height: layerSize.height)

        layer.mask = maskLayer

        // Create animation to reveal mask progressively
        let animation = CAKeyframeAnimation(keyPath: "bounds.size.width")
        animation.calculationMode = .discrete
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = CMTimeGetSeconds(totalDuration)

        var keyTimes: [NSNumber] = []
        var values: [NSNumber] = []

        let totalSeconds = CMTimeGetSeconds(totalDuration)
        let lineStartOffset = words.first?.startTimeSeconds ?? 0

        // Calculate progressive reveal widths
        var currentWidth: CGFloat = 0
        let wordWidthIncrement = layerSize.width / CGFloat(words.count)

        for word in words {
            let wordStartTime = CMTimeAdd(clipStartTime, CMTime(seconds: word.startTimeSeconds, preferredTimescale: 600))
            let normalizedTime = CMTimeGetSeconds(wordStartTime) / totalSeconds

            keyTimes.append(NSNumber(value: normalizedTime))
            values.append(NSNumber(value: Double(currentWidth)))

            currentWidth += wordWidthIncrement
        }

        // Final state: full width
        let lastWordEndTime = words.last?.endTimeSeconds ?? lineStartOffset
        let endTime = CMTimeAdd(clipStartTime, CMTime(seconds: lastWordEndTime, preferredTimescale: 600))
        let normalizedEndTime = CMTimeGetSeconds(endTime) / totalSeconds

        keyTimes.append(NSNumber(value: normalizedEndTime))
        values.append(NSNumber(value: Double(layerSize.width)))

        animation.keyTimes = keyTimes
        animation.values = values

        maskLayer.add(animation, forKey: "revealAnimation")
    }

    // MARK: - Premium Caption Layers

    /// Create CALayers for premium caption styles using PremiumCaptionRenderer
    private nonisolated func createPremiumCaptionLayers(
        from clip: CaptionClip,
        renderSize: CGSize,
        duration: CMTime
    ) -> [CALayer] {
        guard !clip.words.isEmpty else { return [] }

        let style = clip.style
        let fontName = clip.fontName
        let textColorHex = clip.textColorHex
        let highlightColorHex = clip.highlightColorHex
        let positionY = clip.positionY
        let clipScale = clip.scale
        let clipStartTime = clip.cmTimelineStartTime

        // Use resolved segments with pre-computed timing
        let segmentsWithTiming = clip.resolvedSegmentsWithTiming()

        var layers: [CALayer] = []

        for (segIdx, seg) in segmentsWithTiming.enumerated() {
            let segment = seg.lines
            let segmentStartSeconds = seg.startTime
            let segmentEndSeconds = seg.endTime
            let lineTexts = segment.map { $0.map { $0.word }.joined(separator: " ") }

            if style.coloringMode == .currentWord {
                // Render one image per word transition for current-word highlighting
                var flatIndex = 0
                for line in segment {
                    for word in line {
                        let config = PremiumRenderConfig(
                            lines: lineTexts,
                            style: style,
                            renderSize: renderSize,
                            textColorHex: textColorHex,
                            highlightColorHex: highlightColorHex,
                            fontName: fontName,
                            scale: clipScale,
                            currentWordIndex: flatIndex
                        )

                        guard let cgImage = PremiumCaptionRenderer.render(config: config) else {
                            flatIndex += 1
                            continue
                        }

                        let imageLayer = CALayer()
                        imageLayer.contents = cgImage
                        imageLayer.contentsGravity = .resizeAspect
                        imageLayer.contentsScale = 1.0

                        let imageHeight = CGFloat(cgImage.height)
                        imageLayer.bounds = CGRect(origin: .zero, size: CGSize(width: renderSize.width, height: imageHeight))

                        let centerX = renderSize.width / 2
                        let centerY = renderSize.height / 2 + CGFloat(positionY) * (renderSize.height / 2)
                        imageLayer.position = CGPoint(x: centerX, y: centerY)

                        let wordStartTime = CMTimeAdd(clipStartTime, CMTime(seconds: word.startTimeSeconds, preferredTimescale: 600))
                        let wordEndTime = CMTimeAdd(clipStartTime, CMTime(seconds: word.endTimeSeconds, preferredTimescale: 600))

                        addVisibilityAnimation(
                            to: imageLayer,
                            startTime: wordStartTime,
                            endTime: wordEndTime,
                            duration: duration
                        )

                        layers.append(imageLayer)
                        flatIndex += 1
                    }
                }
            } else {
                // perLine or uniform: render one image per segment
                let config = PremiumRenderConfig(
                    lines: lineTexts,
                    style: style,
                    renderSize: renderSize,
                    textColorHex: textColorHex,
                    highlightColorHex: highlightColorHex,
                    fontName: fontName,
                    scale: clipScale
                )

                guard let cgImage = PremiumCaptionRenderer.render(config: config) else { continue }

                let imageLayer = CALayer()
                imageLayer.contents = cgImage
                imageLayer.contentsGravity = .resizeAspect
                imageLayer.contentsScale = 1.0

                let imageHeight = CGFloat(cgImage.height)
                imageLayer.bounds = CGRect(origin: .zero, size: CGSize(width: renderSize.width, height: imageHeight))

                let centerX = renderSize.width / 2
                let centerY = renderSize.height / 2 + CGFloat(positionY) * (renderSize.height / 2)
                imageLayer.position = CGPoint(x: centerX, y: centerY)

                let segStartTime = CMTimeAdd(clipStartTime, CMTime(seconds: segmentStartSeconds, preferredTimescale: 600))
                let segEndTime = CMTimeAdd(clipStartTime, CMTime(seconds: segmentEndSeconds, preferredTimescale: 600))

                addVisibilityAnimation(
                    to: imageLayer,
                    startTime: segStartTime,
                    endTime: segEndTime,
                    duration: duration
                )

                layers.append(imageLayer)
            }
        }

        return layers
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
