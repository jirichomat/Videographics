//
//  GraphicsTrackView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct GraphicsTrackView: View {
    let layer: GraphicsLayer
    @Bindable var viewModel: EditorViewModel
    let timelineViewModel: TimelineViewModel
    var scrollOffset: CGFloat = 0
    var visibleWidth: CGFloat = 800

    // Drag state
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var dragOriginalStartTime: CMTime = .zero
    @State private var draggingClipId: UUID? = nil

    // Trim state
    @State private var isTrimming: Bool = false
    @State private var trimEdge: TrimEdge? = nil
    @State private var trimStartX: CGFloat = 0
    @State private var trimOriginalTimelineStart: CMTime = .zero
    @State private var trimOriginalDuration: CMTime = .zero
    @State private var trimmingClipId: UUID? = nil

    private let trimHandleHitWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemGroupedBackground))

                // Graphics clips
                ForEach(layer.clips) { clip in
                    graphicsClipView(for: clip, in: geometry)
                }

                // Track label
                HStack(spacing: 2) {
                    Image(systemName: "photo")
                        .font(.caption2)
                    Text(layer.name)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(width: AppConstants.trackLabelWidth, height: geometry.size.height)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    @ViewBuilder
    private func graphicsClipView(for clip: GraphicsClip, in geometry: GeometryProxy) -> some View {
        let isBeingDragged = isDragging && draggingClipId == clip.id
        let isBeingTrimmed = isTrimming && trimmingClipId == clip.id
        let clipWidth = CGFloat(clip.cmDuration.seconds) * viewModel.pixelsPerSecond
        let xPosition = timelineViewModel.xPosition(
            for: clip.cmTimelineStartTime,
            pixelsPerSecond: viewModel.pixelsPerSecond
        ) + AppConstants.trackLabelWidth

        // Graphics clip visual
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(0.7))

            // Trim handles
            HStack(spacing: 0) {
                // Leading trim handle
                Rectangle()
                    .fill(isBeingTrimmed && trimEdge == .leading ? Color.yellow : Color.green)
                    .frame(width: 6)
                    .cornerRadius(4, corners: [.topLeft, .bottomLeft])

                Spacer()

                // Trailing trim handle
                Rectangle()
                    .fill(isBeingTrimmed && trimEdge == .trailing ? Color.yellow : Color.green)
                    .frame(width: 6)
                    .cornerRadius(4, corners: [.topRight, .bottomRight])
            }

            // Image preview (thumbnail)
            HStack(spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(.caption2)
                    .foregroundColor(.white)

                Text("Image")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: max(clipWidth, 20), height: geometry.size.height - 8)
        .offset(
            x: xPosition,
            y: isBeingDragged ? dragOffset.height : 0
        )
        .zIndex(isBeingDragged ? 100 : 0)
        .contentShape(Rectangle())
        .gesture(
            viewModel.currentTool == .move ? dragGesture(for: clip) : nil
        )
        .simultaneousGesture(
            trimGesture(for: clip, in: geometry)
        )
    }

    // MARK: - Drag Gesture

    private func dragGesture(for clip: GraphicsClip) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    dragOriginalStartTime = clip.cmTimelineStartTime
                    draggingClipId = clip.id
                }

                isDragging = true

                // Update horizontal position
                let newTime = timelineViewModel.time(
                    for: value.location.x - AppConstants.trackLabelWidth,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                )
                let clampedTime = max(newTime, CMTime.zero)
                clip.setTimelineStartTime(clampedTime)

                dragOffset = CGSize(width: 0, height: value.translation.height)
            }
            .onEnded { _ in
                isDragging = false
                draggingClipId = nil
                dragOffset = .zero

                viewModel.project.modifiedAt = Date()
                Task {
                    await viewModel.rebuildComposition()
                }
            }
    }

    // MARK: - Trim Gesture

    private func trimGesture(for clip: GraphicsClip, in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let clipStartX = timelineViewModel.xPosition(
                    for: clip.cmTimelineStartTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth

                let clipWidth = CGFloat(clip.cmDuration.seconds) * viewModel.pixelsPerSecond
                let clipEndX = clipStartX + clipWidth

                // Determine trim edge on first drag
                if !isTrimming {
                    let startLocationX = value.startLocation.x

                    if abs(startLocationX - clipStartX) < trimHandleHitWidth {
                        isTrimming = true
                        trimmingClipId = clip.id
                        trimEdge = .leading
                        trimStartX = value.startLocation.x
                        trimOriginalTimelineStart = clip.cmTimelineStartTime
                        trimOriginalDuration = clip.cmDuration
                    } else if abs(startLocationX - clipEndX) < trimHandleHitWidth {
                        isTrimming = true
                        trimmingClipId = clip.id
                        trimEdge = .trailing
                        trimStartX = value.startLocation.x
                        trimOriginalTimelineStart = clip.cmTimelineStartTime
                        trimOriginalDuration = clip.cmDuration
                    }
                }

                // Apply trim
                if isTrimming {
                    let deltaX = value.location.x - trimStartX
                    let deltaTime = timelineViewModel.time(
                        for: abs(deltaX),
                        pixelsPerSecond: viewModel.pixelsPerSecond
                    )

                    let minDuration = CMTime(seconds: 0.5, preferredTimescale: 600)

                    if trimEdge == .leading {
                        if deltaX > 0 {
                            // Trim in from left
                            let newTimelineStart = CMTimeAdd(trimOriginalTimelineStart, deltaTime)
                            let newDuration = CMTimeSubtract(trimOriginalDuration, deltaTime)
                            if CMTimeCompare(newDuration, minDuration) >= 0 {
                                clip.setTimelineStartTime(newTimelineStart)
                                clip.setDuration(newDuration)
                            }
                        } else {
                            // Extend left
                            let newTimelineStart = CMTimeSubtract(trimOriginalTimelineStart, deltaTime)
                            let newDuration = CMTimeAdd(trimOriginalDuration, deltaTime)
                            if CMTimeCompare(newTimelineStart, .zero) >= 0 {
                                clip.setTimelineStartTime(newTimelineStart)
                                clip.setDuration(newDuration)
                            }
                        }
                    } else if trimEdge == .trailing {
                        if deltaX < 0 {
                            // Trim in from right
                            let newDuration = CMTimeSubtract(trimOriginalDuration, deltaTime)
                            if CMTimeCompare(newDuration, minDuration) >= 0 {
                                clip.setDuration(newDuration)
                            }
                        } else {
                            // Extend right
                            let newDuration = CMTimeAdd(trimOriginalDuration, deltaTime)
                            clip.setDuration(newDuration)
                        }
                    }
                }
            }
            .onEnded { _ in
                if isTrimming {
                    viewModel.project.modifiedAt = Date()
                    Task {
                        await viewModel.rebuildComposition()
                    }
                }

                isTrimming = false
                trimmingClipId = nil
                trimEdge = nil
            }
    }
}

#Preview {
    GraphicsTrackView(
        layer: GraphicsLayer(name: "Graphics", zIndex: 101),
        viewModel: EditorViewModel(project: Project(name: "Test")),
        timelineViewModel: TimelineViewModel()
    )
    .frame(height: 40)
}
