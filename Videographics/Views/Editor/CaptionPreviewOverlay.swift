//
//  CaptionPreviewOverlay.swift
//  Videographics
//
//  Renders caption overlays during video preview using SwiftUI
//  (AVVideoCompositionCoreAnimationTool can't be used with AVPlayerItem)
//

import SwiftUI
import CoreMedia

/// Displays captions synced with video playback as a SwiftUI overlay
struct CaptionPreviewOverlay: View {
    @Bindable var viewModel: EditorViewModel
    let videoSize: CGSize

    var body: some View {
        ZStack {
            // Render each visible caption
            ForEach(visibleCaptions, id: \.clip.id) { caption in
                CaptionTextView(
                    caption: caption,
                    currentTime: viewModel.currentTime,
                    videoSize: videoSize
                )
            }
        }
    }

    /// Get captions that should be visible at the current time
    private var visibleCaptions: [VisibleCaption] {
        guard let timeline = viewModel.project.timeline else { return [] }

        let currentSeconds = viewModel.currentTime.seconds
        var result: [VisibleCaption] = []

        for layer in timeline.captionLayers where layer.isVisible {
            for clip in layer.clips {
                let clipStart = clip.cmTimelineStartTime.seconds
                let clipEnd = clip.cmTimelineEndTime.seconds

                // Check if current time is within this caption clip
                if currentSeconds >= clipStart && currentSeconds < clipEnd {
                    result.append(VisibleCaption(clip: clip, layer: layer))
                }
            }
        }

        return result
    }
}

/// Wrapper to identify visible captions
private struct VisibleCaption {
    let clip: CaptionClip
    let layer: CaptionLayer
}

/// Renders a single caption with proper styling
private struct CaptionTextView: View {
    let caption: VisibleCaption
    let currentTime: CMTime
    let videoSize: CGSize

    var body: some View {
        let clip = caption.clip
        let relativeTime = currentTime.seconds - clip.cmTimelineStartTime.seconds

        if clip.style.usesPremiumRenderer {
            PremiumCaptionPreview(clip: clip, relativeTime: relativeTime, videoSize: videoSize)
        } else {
            standardCaptionView(clip: clip, relativeTime: relativeTime)
        }
    }

    @ViewBuilder
    private func standardCaptionView(clip: CaptionClip, relativeTime: Double) -> some View {
        let visibleText = getVisibleText(clip: clip, relativeTime: relativeTime)

        if !visibleText.isEmpty {
            Text(visibleText)
                .font(.custom(clip.fontName, size: CGFloat(clip.fontSize) * CGFloat(clip.scale) * scaleFactor))
                .foregroundColor(clip.textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, clip.showBackground ? 12 : 0)
                .padding(.vertical, clip.showBackground ? 8 : 0)
                .background(
                    clip.showBackground
                        ? RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.7))
                        : nil
                )
                .position(
                    x: videoSize.width / 2 + CGFloat(clip.positionX) * (videoSize.width / 2),
                    y: videoSize.height / 2 - CGFloat(clip.positionY) * (videoSize.height / 2)
                )
        }
    }

    /// Scale factor for preview (video preview is smaller than render size)
    private var scaleFactor: CGFloat {
        videoSize.width / 1080.0
    }

    /// Get the text that should be visible at the current relative time
    private func getVisibleText(clip: CaptionClip, relativeTime: Double) -> String {
        let words = clip.words
        guard !words.isEmpty else { return "" }

        if clip.style.hasWordAnimation {
            let visibleWords = words.filter { word in
                relativeTime >= word.startTimeSeconds
            }
            return visibleWords.map { $0.word }.joined(separator: " ")
        } else {
            let lines = clip.wordsGroupedIntoLines()
            for line in lines {
                guard let first = line.first, let last = line.last else { continue }
                if relativeTime >= first.startTimeSeconds && relativeTime < last.endTimeSeconds + 0.5 {
                    return line.map { $0.word }.joined(separator: " ")
                }
            }
            return clip.fullText
        }
    }
}

/// Preview for premium caption styles using PremiumCaptionRenderer
private struct PremiumCaptionPreview: View {
    let clip: CaptionClip
    let relativeTime: Double
    let videoSize: CGSize

    @State private var imageCache: [String: UIImage] = [:]

    var body: some View {
        if let uiImage = renderedImage {
            let scale = videoSize.width / 1080.0
            let imageHeight = CGFloat(uiImage.size.height) * scale
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: videoSize.width, height: imageHeight)
                .position(
                    // Image is full-width (text already centered/aligned inside it).
                    // Only positionY shifts vertically.
                    x: videoSize.width / 2,
                    y: videoSize.height / 2 - CGFloat(clip.positionY) * (videoSize.height / 2)
                )
        }
    }

    private var renderedImage: UIImage? {
        let style = clip.style
        guard !clip.words.isEmpty else { return nil }

        // Use resolved segments with pre-computed timing
        let segmentsWithTiming = clip.resolvedSegmentsWithTiming()

        // Find the segment active at relativeTime
        var activeSegment: [[CaptionWord]]?
        var segmentIndex = 0
        for (idx, seg) in segmentsWithTiming.enumerated() {
            // Add small grace period for last segment
            let endTime = idx == segmentsWithTiming.count - 1 ? seg.endTime + 0.3 : seg.endTime
            if relativeTime >= seg.startTime && relativeTime < endTime {
                activeSegment = seg.lines
                segmentIndex = idx
                break
            }
        }

        guard let segment = activeSegment else { return nil }

        let lineTexts = segment.map { $0.map { $0.word }.joined(separator: " ") }

        // For currentWord mode, find the flat word index
        var currentWordIndex: Int? = nil
        if style.coloringMode == .currentWord {
            var flatIdx = 0
            for line in segment {
                for word in line {
                    if relativeTime >= word.startTimeSeconds && relativeTime < word.endTimeSeconds {
                        currentWordIndex = flatIdx
                    }
                    flatIdx += 1
                }
            }
        }

        // Cache key
        let cacheKey = "\(segmentIndex)-\(currentWordIndex ?? -1)"
        if let cached = imageCache[cacheKey] {
            return cached
        }

        // Render at reference size 1080x1920
        let renderSize = CGSize(width: 1080, height: 1920)
        let config = PremiumRenderConfig(
            lines: lineTexts,
            style: style,
            renderSize: renderSize,
            textColorHex: clip.textColorHex,
            highlightColorHex: clip.highlightColorHex,
            fontName: clip.fontName,
            scale: clip.scale,
            currentWordIndex: currentWordIndex
        )

        guard let cgImage = PremiumCaptionRenderer.render(config: config) else { return nil }
        let image = UIImage(cgImage: cgImage)

        // Cache the result
        DispatchQueue.main.async {
            imageCache[cacheKey] = image
        }

        return image
    }
}

#Preview {
    ZStack {
        Color.black
        Text("Preview placeholder")
            .foregroundColor(.white)
    }
    .frame(width: 300, height: 600)
}
