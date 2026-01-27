//
//  CanvasClipRenderer.swift
//  Videographics
//
//  Canvas-based high-performance clip rendering for timeline.
//  Draws all clips in a single pass using Core Graphics for improved
//  scrolling performance and reduced memory usage.
//

import SwiftUI
import UIKit
import CoreMedia

/// Configuration for rendering a single clip on the Canvas
struct ClipRenderInfo: Identifiable {
    let id: UUID
    let xPosition: CGFloat
    let width: CGFloat
    let isSelected: Bool
    let thumbnails: [Data]
    let showBladeIndicator: Bool
    let showTrimHandles: Bool
    let activeTrimEdge: TrimEdge?
    let canTrimLeadingExtend: Bool
    let canTrimTrailingExtend: Bool
}

/// High-performance Canvas-based renderer for video clips
struct CanvasClipRenderer: View {
    let clips: [ClipRenderInfo]
    let trackHeight: CGFloat
    let visibleRange: ClosedRange<CGFloat>

    // Rendering constants
    private let cornerRadius: CGFloat = 4
    private let borderWidth: CGFloat = 1
    private let selectedBorderWidth: CGFloat = 2
    private let trimHandleWidth: CGFloat = 12
    private let gripLineWidth: CGFloat = 4
    private let gripLineHeight: CGFloat = 2
    private let gripLineSpacing: CGFloat = 3

    // Colors (cached for performance)
    private let clipFillColor = Color.blue.opacity(0.3)
    private let clipBorderColor = Color.blue
    private let selectedBorderColor = Color.yellow
    private let trimHandleColor = Color.yellow.opacity(0.8)
    private let trimHandleActiveColor = Color.yellow
    private let trimHandleInactiveColor = Color.white.opacity(0.25)
    private let gripColor = Color.black.opacity(0.4)
    private let bladeColor = Color.red.opacity(0.3)

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

                drawClip(context: context, clip: clip, trackHeight: trackContentHeight, yOffset: yOffset)
            }
        }
        .frame(height: trackHeight)
    }

    // MARK: - Drawing Methods

    private func drawClip(context: GraphicsContext, clip: ClipRenderInfo, trackHeight: CGFloat, yOffset: CGFloat) {
        let rect = CGRect(x: clip.xPosition, y: yOffset, width: clip.width, height: trackHeight)
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        let clipPath = Path(roundedRect.path(in: rect).cgPath)

        // 1. Draw background fill
        context.fill(clipPath, with: .color(clipFillColor))

        // 2. Draw thumbnails if available
        if !clip.thumbnails.isEmpty {
            drawThumbnails(context: context, clip: clip, rect: rect)
        } else {
            // Draw gradient fallback
            drawGradientFallback(context: context, rect: rect)
        }

        // 3. Draw border (selection state)
        let borderColor = clip.isSelected ? selectedBorderColor : clipBorderColor
        let lineWidth = clip.isSelected ? selectedBorderWidth : borderWidth
        context.stroke(clipPath, with: .color(borderColor), lineWidth: lineWidth)

        // 4. Draw trim handles if needed
        if clip.showTrimHandles && clip.width > trimHandleWidth * 3 {
            drawTrimHandles(context: context, clip: clip, rect: rect)
        }

        // 5. Draw blade indicator if in blade mode
        if clip.showBladeIndicator {
            drawBladeIndicator(context: context, rect: rect)
        }
    }

    private func drawThumbnails(context: GraphicsContext, clip: ClipRenderInfo, rect: CGRect) {
        let thumbnailCount = clip.thumbnails.count
        guard thumbnailCount > 0 else { return }

        let thumbnailWidth = rect.width / CGFloat(thumbnailCount)

        // Create a clipped context for thumbnails
        var clippedContext = context
        let clipPath = Path(RoundedRectangle(cornerRadius: cornerRadius).path(in: rect).cgPath)
        clippedContext.clip(to: clipPath)

        for (index, thumbnailData) in clip.thumbnails.enumerated() {
            guard let uiImage = UIImage(data: thumbnailData) else { continue }

            let thumbnailRect = CGRect(
                x: rect.minX + CGFloat(index) * thumbnailWidth,
                y: rect.minY,
                width: thumbnailWidth,
                height: rect.height
            )

            // Draw thumbnail with aspect fill using resolved image
            let image = Image(uiImage: uiImage)
            let resolvedImage = clippedContext.resolve(image)
            clippedContext.draw(resolvedImage, in: thumbnailRect)
        }
    }

    private func drawGradientFallback(context: GraphicsContext, rect: CGRect) {
        let clipPath = Path(RoundedRectangle(cornerRadius: cornerRadius).path(in: rect).cgPath)

        let gradient = Gradient(colors: [
            Color.blue.opacity(0.4),
            Color.blue.opacity(0.2)
        ])

        context.fill(
            clipPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
    }

    private func drawTrimHandles(context: GraphicsContext, clip: ClipRenderInfo, rect: CGRect) {
        // Leading handle
        drawTrimHandle(
            context: context,
            rect: rect,
            edge: .leading,
            isActive: clip.activeTrimEdge == .leading,
            isSelected: clip.isSelected,
            canExtend: clip.canTrimLeadingExtend
        )

        // Trailing handle
        drawTrimHandle(
            context: context,
            rect: rect,
            edge: .trailing,
            isActive: clip.activeTrimEdge == .trailing,
            isSelected: clip.isSelected,
            canExtend: clip.canTrimTrailingExtend
        )
    }

    private func drawTrimHandle(
        context: GraphicsContext,
        rect: CGRect,
        edge: TrimEdge,
        isActive: Bool,
        isSelected: Bool,
        canExtend: Bool
    ) {
        // Determine handle position
        let handleRect: CGRect
        if edge == .leading {
            handleRect = CGRect(x: rect.minX, y: rect.minY, width: trimHandleWidth, height: rect.height)
        } else {
            handleRect = CGRect(x: rect.maxX - trimHandleWidth, y: rect.minY, width: trimHandleWidth, height: rect.height)
        }

        // Determine colors
        let backgroundColor: Color
        if isActive {
            backgroundColor = trimHandleActiveColor
        } else if isSelected {
            backgroundColor = trimHandleColor
        } else {
            backgroundColor = trimHandleInactiveColor
        }

        // Create rounded rect path with proper corners
        let corners: UIRectCorner = edge == .leading ? [.topLeft, .bottomLeft] : [.topRight, .bottomRight]
        let handlePath = Path(
            UIBezierPath(
                roundedRect: handleRect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
            ).cgPath
        )

        // Draw handle background
        context.fill(handlePath, with: .color(backgroundColor))

        // Draw grip lines
        let centerX = handleRect.midX
        let centerY = handleRect.midY
        let gripStartY = centerY - gripLineSpacing - gripLineHeight

        for i in 0..<3 {
            let y = gripStartY + CGFloat(i) * (gripLineHeight + gripLineSpacing)
            let gripRect = CGRect(
                x: centerX - gripLineWidth / 2,
                y: y,
                width: gripLineWidth,
                height: gripLineHeight
            )
            let gripPath = Path(RoundedRectangle(cornerRadius: 1).path(in: gripRect).cgPath)
            context.fill(gripPath, with: .color(gripColor))
        }

        // Draw extension chevron if can extend and selected (but not active)
        if canExtend && !isActive && isSelected {
            let chevronX = edge == .leading ? handleRect.minX + 2 : handleRect.maxX - 6
            let chevronY = rect.maxY - 12

            drawChevron(
                context: context,
                at: CGPoint(x: chevronX, y: chevronY),
                direction: edge == .leading ? .left : .right
            )
        }
    }

    private func drawChevron(context: GraphicsContext, at point: CGPoint, direction: ChevronDirection) {
        var path = Path()
        let size: CGFloat = 4

        switch direction {
        case .left:
            path.move(to: CGPoint(x: point.x + size, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y + size))
            path.addLine(to: CGPoint(x: point.x + size, y: point.y + size * 2))
        case .right:
            path.move(to: CGPoint(x: point.x, y: point.y))
            path.addLine(to: CGPoint(x: point.x + size, y: point.y + size))
            path.addLine(to: CGPoint(x: point.x, y: point.y + size * 2))
        }

        context.stroke(path, with: .color(Color.green.opacity(0.8)), lineWidth: 1.5)
    }

    private func drawBladeIndicator(context: GraphicsContext, rect: CGRect) {
        // Draw vertical dashed lines pattern
        let lineSpacing: CGFloat = 40
        let numberOfLines = max(1, Int(rect.width / lineSpacing))

        for i in 0..<numberOfLines {
            let x = rect.minX + CGFloat(i + 1) * (rect.width / CGFloat(numberOfLines + 1))

            var linePath = Path()
            linePath.move(to: CGPoint(x: x, y: rect.minY))
            linePath.addLine(to: CGPoint(x: x, y: rect.maxY))

            context.stroke(linePath, with: .color(bladeColor), lineWidth: 1)
        }

        // Draw scissors icon background (simplified circle)
        let iconSize: CGFloat = 22
        let iconRect = CGRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )

        let circlePath = Path(ellipseIn: iconRect)
        context.fill(circlePath, with: .color(bladeColor))

        // Draw scissors symbol (simplified as X for performance)
        let symbolPadding: CGFloat = 6
        var scissorsPath = Path()
        scissorsPath.move(to: CGPoint(x: iconRect.minX + symbolPadding, y: iconRect.minY + symbolPadding))
        scissorsPath.addLine(to: CGPoint(x: iconRect.maxX - symbolPadding, y: iconRect.maxY - symbolPadding))
        scissorsPath.move(to: CGPoint(x: iconRect.maxX - symbolPadding, y: iconRect.minY + symbolPadding))
        scissorsPath.addLine(to: CGPoint(x: iconRect.minX + symbolPadding, y: iconRect.maxY - symbolPadding))

        context.stroke(scissorsPath, with: .color(.white.opacity(0.6)), lineWidth: 2)
    }

    private enum ChevronDirection {
        case left, right
    }
}

// MARK: - Helper Extension for Creating Render Info

extension ClipRenderInfo {
    init(
        clip: VideoClip,
        xPosition: CGFloat,
        pixelsPerSecond: CGFloat,
        isSelected: Bool,
        showBladeIndicator: Bool,
        showTrimHandles: Bool,
        activeTrimEdge: TrimEdge?
    ) {
        self.id = clip.id
        self.xPosition = xPosition
        self.width = CGFloat(clip.cmDuration.seconds) * pixelsPerSecond
        self.isSelected = isSelected
        self.thumbnails = clip.thumbnails
        self.showBladeIndicator = showBladeIndicator
        self.showTrimHandles = showTrimHandles
        self.activeTrimEdge = activeTrimEdge

        // Calculate trim extension capabilities
        self.canTrimLeadingExtend = CMTimeCompare(clip.cmSourceStartTime, .zero) > 0
        let usedDuration = CMTimeAdd(clip.cmSourceStartTime, clip.cmDuration)
        self.canTrimTrailingExtend = CMTimeCompare(usedDuration, clip.cmOriginalDuration) < 0
    }
}

#Preview {
    CanvasClipRenderer(
        clips: [
            ClipRenderInfo(
                id: UUID(),
                xPosition: 50,
                width: 200,
                isSelected: false,
                thumbnails: [],
                showBladeIndicator: false,
                showTrimHandles: true,
                activeTrimEdge: nil,
                canTrimLeadingExtend: true,
                canTrimTrailingExtend: true
            ),
            ClipRenderInfo(
                id: UUID(),
                xPosition: 260,
                width: 150,
                isSelected: true,
                thumbnails: [],
                showBladeIndicator: false,
                showTrimHandles: true,
                activeTrimEdge: nil,
                canTrimLeadingExtend: false,
                canTrimTrailingExtend: true
            ),
            ClipRenderInfo(
                id: UUID(),
                xPosition: 420,
                width: 100,
                isSelected: false,
                thumbnails: [],
                showBladeIndicator: true,
                showTrimHandles: false,
                activeTrimEdge: nil,
                canTrimLeadingExtend: true,
                canTrimTrailingExtend: false
            )
        ],
        trackHeight: 52,
        visibleRange: 0...800
    )
    .frame(width: 800, height: 60)
    .background(Color(.secondarySystemGroupedBackground))
    .padding()
}
