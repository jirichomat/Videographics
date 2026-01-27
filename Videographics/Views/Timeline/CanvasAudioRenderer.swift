//
//  CanvasAudioRenderer.swift
//  Videographics
//
//  Canvas-based high-performance audio clip rendering for timeline.
//  Draws all audio clips in a single pass using Core Graphics.
//

import SwiftUI
import UIKit
import CoreMedia

/// Configuration for rendering a single audio clip on the Canvas
struct AudioClipRenderInfo: Identifiable {
    let id: UUID
    let xPosition: CGFloat
    let width: CGFloat
    let isSelected: Bool
}

/// High-performance Canvas-based renderer for audio clips
struct CanvasAudioRenderer: View {
    let clips: [AudioClipRenderInfo]
    let trackHeight: CGFloat
    let visibleRange: ClosedRange<CGFloat>

    // Rendering constants
    private let cornerRadius: CGFloat = 4
    private let borderWidth: CGFloat = 1
    private let selectedBorderWidth: CGFloat = 2

    // Colors
    private let clipFillColor = Color.green.opacity(0.6)
    private let clipBorderColor = Color.green
    private let selectedBorderColor = Color.yellow

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let trackContentHeight = trackHeight - 8
            let yOffset: CGFloat = 4

            for clip in clips {
                // Skip clips outside visible range for performance
                let clipEnd = clip.xPosition + clip.width
                guard clipEnd >= visibleRange.lowerBound && clip.xPosition <= visibleRange.upperBound else {
                    continue
                }

                drawAudioClip(context: context, clip: clip, trackHeight: trackContentHeight, yOffset: yOffset)
            }
        }
        .frame(height: trackHeight)
    }

    private func drawAudioClip(context: GraphicsContext, clip: AudioClipRenderInfo, trackHeight: CGFloat, yOffset: CGFloat) {
        let rect = CGRect(x: clip.xPosition, y: yOffset, width: clip.width, height: trackHeight)
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        let clipPath = Path(roundedRect.path(in: rect).cgPath)

        // Draw fill
        context.fill(clipPath, with: .color(clipFillColor))

        // Draw waveform visualization (simple bars pattern for performance)
        drawWaveformPattern(context: context, rect: rect)

        // Draw border
        let borderColor = clip.isSelected ? selectedBorderColor : clipBorderColor
        let lineWidth = clip.isSelected ? selectedBorderWidth : borderWidth
        context.stroke(clipPath, with: .color(borderColor), lineWidth: lineWidth)
    }

    private func drawWaveformPattern(context: GraphicsContext, rect: CGRect) {
        // Simple waveform visualization using vertical bars
        let barWidth: CGFloat = 3
        let barSpacing: CGFloat = 2
        let totalBarWidth = barWidth + barSpacing
        let numberOfBars = max(1, Int(rect.width / totalBarWidth))

        // Create a clipped context
        var clippedContext = context
        let clipPath = Path(RoundedRectangle(cornerRadius: cornerRadius).path(in: rect).cgPath)
        clippedContext.clip(to: clipPath)

        // Use a pseudo-random pattern based on position
        for i in 0..<numberOfBars {
            let x = rect.minX + CGFloat(i) * totalBarWidth + barSpacing / 2

            // Generate pseudo-random height (deterministic based on index for consistent rendering)
            let heightFactor = 0.3 + 0.5 * abs(sin(Double(i) * 0.7 + 0.3))
            let barHeight = rect.height * CGFloat(heightFactor)

            let barRect = CGRect(
                x: x,
                y: rect.midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )

            let barPath = Path(RoundedRectangle(cornerRadius: 1).path(in: barRect).cgPath)
            clippedContext.fill(barPath, with: .color(Color.green.opacity(0.3)))
        }
    }
}

// MARK: - Helper Extension

extension AudioClipRenderInfo {
    init(
        clip: AudioClip,
        xPosition: CGFloat,
        pixelsPerSecond: CGFloat,
        isSelected: Bool
    ) {
        self.id = clip.id
        self.xPosition = xPosition
        self.width = CGFloat(clip.cmDuration.seconds) * pixelsPerSecond
        self.isSelected = isSelected
    }
}

#Preview {
    CanvasAudioRenderer(
        clips: [
            AudioClipRenderInfo(
                id: UUID(),
                xPosition: 50,
                width: 200,
                isSelected: false
            ),
            AudioClipRenderInfo(
                id: UUID(),
                xPosition: 260,
                width: 150,
                isSelected: true
            ),
            AudioClipRenderInfo(
                id: UUID(),
                xPosition: 420,
                width: 100,
                isSelected: false
            )
        ],
        trackHeight: 40,
        visibleRange: 0...800
    )
    .frame(width: 800, height: 40)
    .background(Color(.secondarySystemGroupedBackground))
    .padding()
}
