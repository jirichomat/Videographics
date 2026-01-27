//
//  ClipView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

/// Edge being trimmed
enum TrimEdge {
    case leading
    case trailing
}

struct ClipView: View {
    let clip: VideoClip
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    var showBladeIndicator: Bool = false
    var showTrimHandles: Bool = false
    var activeTrimEdge: TrimEdge? = nil

    @State private var hoverLocation: CGPoint? = nil

    // Trim handle constants
    private let trimHandleWidth: CGFloat = 12
    private let trimHandleCornerRadius: CGFloat = 4

    private var clipWidth: CGFloat {
        CGFloat(clip.cmDuration.seconds) * pixelsPerSecond
    }

    /// Check if clip can be trimmed from the leading edge (can extend back)
    var canTrimLeadingExtend: Bool {
        CMTimeCompare(clip.cmSourceStartTime, .zero) > 0
    }

    /// Check if clip can be trimmed from the trailing edge (can extend forward)
    var canTrimTrailingExtend: Bool {
        let usedDuration = CMTimeAdd(clip.cmSourceStartTime, clip.cmDuration)
        return CMTimeCompare(usedDuration, clip.cmOriginalDuration) < 0
    }

    var body: some View {
        ZStack {
            // Background with thumbnails
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue.opacity(0.3))
                .frame(width: clipWidth, height: trackHeight)
                .overlay(
                    thumbnailsView
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                )

            // Selection border
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: clipWidth, height: trackHeight)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue, lineWidth: 1)
                    .frame(width: clipWidth, height: trackHeight)
            }

            // Trim handles (only when trim mode active or selected)
            if showTrimHandles && clipWidth > trimHandleWidth * 3 {
                trimHandlesOverlay
            }

            // Blade mode indicator - dotted line overlay
            if showBladeIndicator {
                bladeOverlay
            }
        }
        .frame(width: clipWidth, height: trackHeight)
        .contentShape(Rectangle())
    }

    // MARK: - Trim Handles

    @ViewBuilder
    private var trimHandlesOverlay: some View {
        HStack {
            // Leading (left) trim handle
            trimHandle(edge: .leading, isActive: activeTrimEdge == .leading)

            Spacer()

            // Trailing (right) trim handle
            trimHandle(edge: .trailing, isActive: activeTrimEdge == .trailing)
        }
        .frame(width: clipWidth, height: trackHeight)
    }

    @ViewBuilder
    private func trimHandle(edge: TrimEdge, isActive: Bool) -> some View {
        let canExtend = edge == .leading ? canTrimLeadingExtend : canTrimTrailingExtend

        // Different styles based on state
        let backgroundColor: Color = {
            if isActive {
                return Color.yellow
            } else if isSelected {
                return Color.yellow.opacity(0.8)
            } else {
                return Color.white.opacity(0.25)
            }
        }()

        let gripColor: Color = {
            if isActive {
                return Color.black.opacity(0.6)
            } else if isSelected {
                return Color.black.opacity(0.4)
            } else {
                return Color.black.opacity(0.3)
            }
        }()

        ZStack {
            // Handle background
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: edge == .leading ? trimHandleCornerRadius : 0,
                    bottomLeading: edge == .leading ? trimHandleCornerRadius : 0,
                    bottomTrailing: edge == .trailing ? trimHandleCornerRadius : 0,
                    topTrailing: edge == .trailing ? trimHandleCornerRadius : 0
                )
            )
            .fill(backgroundColor)
            .frame(width: trimHandleWidth, height: trackHeight)

            // Grip lines (visual indicator)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(gripColor)
                        .frame(width: 4, height: 2)
                }
            }

            // Extension indicator (arrows when can extend) - only show when selected
            if canExtend && !isActive && isSelected {
                Image(systemName: edge == .leading ? "chevron.left" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.8))
                    .offset(x: edge == .leading ? -2 : 2, y: trackHeight / 2 - 8)
            }
        }
    }

    @ViewBuilder
    private var bladeOverlay: some View {
        GeometryReader { geometry in
            // Scissors icon in center to indicate blade mode
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "scissors")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(4)
                        .background(Color.red.opacity(0.3))
                        .clipShape(Circle())
                    Spacer()
                }
                Spacer()
            }

            // Vertical dashed line pattern to show where cuts can be made
            HStack(spacing: 20) {
                ForEach(0..<max(1, Int(clipWidth / 40)), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 1, height: trackHeight)
                }
            }
            .frame(width: clipWidth, height: trackHeight)
        }
    }

    @ViewBuilder
    private var thumbnailsView: some View {
        // Use lazy thumbnail loading for memory efficiency
        LazyThumbnailView(
            clip: clip,
            clipWidth: clipWidth,
            trackHeight: trackHeight
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        // Normal clip
        ClipView(
            clip: VideoClip(
                assetURL: URL(string: "file://test")!,
                duration: CMTime(seconds: 5, preferredTimescale: 600)
            ),
            isSelected: false,
            pixelsPerSecond: 50,
            trackHeight: 52
        )

        // Selected with trim handles
        ClipView(
            clip: VideoClip(
                assetURL: URL(string: "file://test")!,
                duration: CMTime(seconds: 5, preferredTimescale: 600)
            ),
            isSelected: true,
            pixelsPerSecond: 50,
            trackHeight: 52,
            showTrimHandles: true
        )

        // Actively trimming leading edge
        ClipView(
            clip: VideoClip(
                assetURL: URL(string: "file://test")!,
                duration: CMTime(seconds: 5, preferredTimescale: 600)
            ),
            isSelected: true,
            pixelsPerSecond: 50,
            trackHeight: 52,
            showTrimHandles: true,
            activeTrimEdge: .leading
        )
    }
    .padding()
}
