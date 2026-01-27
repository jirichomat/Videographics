//
//  VideoTrackView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct VideoTrackView: View {
    let layer: VideoLayer
    @Bindable var viewModel: EditorViewModel
    let timelineViewModel: TimelineViewModel
    let trackHeight: CGFloat
    var scrollOffset: CGFloat = 0
    var visibleWidth: CGFloat = 800

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var dragOriginalStartTime: CMTime = .zero
    @State private var draggingClipId: UUID? = nil

    // Trim state
    @State private var isTrimming: Bool = false
    @State private var trimEdge: TrimEdge? = nil
    @State private var trimStartX: CGFloat = 0
    @State private var trimOriginalSourceStart: CMTime = .zero
    @State private var trimOriginalTimelineStart: CMTime = .zero
    @State private var trimOriginalDuration: CMTime = .zero
    @State private var trimBeforeSnapshot: VideoClipTimingSnapshot?
    @State private var trimmingClipId: UUID? = nil

    // Trim handle detection width
    private let trimHandleHitWidth: CGFloat = 20

    // Computed visible range for Canvas optimization
    private var visibleRange: ClosedRange<CGFloat> {
        let start = max(0, scrollOffset - 100)
        let end = scrollOffset + visibleWidth + 100
        return start...end
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemGroupedBackground))

                // Canvas-based clip rendering (high performance)
                canvasClipLayer(in: geometry)

                // Gesture overlay layer (transparent hit areas for interactions)
                gestureOverlayLayer(in: geometry)

                // Transition indicators and placeholders
                transitionOverlays(in: geometry)

                // Track label (rendered last so it appears on top of clips)
                Text(layer.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: AppConstants.trackLabelWidth, height: geometry.size.height)
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    // MARK: - Canvas Clip Rendering

    @ViewBuilder
    private func canvasClipLayer(in geometry: GeometryProxy) -> some View {
        let clipRenderInfos = layer.clips.map { clip -> ClipRenderInfo in
            let isBeingTrimmed = isTrimming && trimmingClipId == clip.id
            let isSelected = viewModel.selectedClip?.id == clip.id

            return ClipRenderInfo(
                clip: clip,
                xPosition: timelineViewModel.xPosition(
                    for: clip.cmTimelineStartTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth,
                pixelsPerSecond: viewModel.pixelsPerSecond,
                isSelected: isSelected,
                showBladeIndicator: viewModel.currentTool == .blade,
                showTrimHandles: true,
                activeTrimEdge: isBeingTrimmed ? trimEdge : nil
            )
        }

        CanvasClipRenderer(
            clips: clipRenderInfos,
            trackHeight: geometry.size.height,
            visibleRange: visibleRange
        )
    }

    // MARK: - Gesture Overlay Layer

    @ViewBuilder
    private func gestureOverlayLayer(in geometry: GeometryProxy) -> some View {
        ForEach(layer.clips) { clip in
            let isBeingDragged = isDragging && draggingClipId == clip.id
            let clipWidth = CGFloat(clip.cmDuration.seconds) * viewModel.pixelsPerSecond
            let xPosition = timelineViewModel.xPosition(
                for: clip.cmTimelineStartTime,
                pixelsPerSecond: viewModel.pixelsPerSecond
            ) + AppConstants.trackLabelWidth

            // Transparent hit area for gestures
            Color.clear
                .frame(width: clipWidth, height: geometry.size.height - 8)
                .contentShape(Rectangle())
                .offset(
                    x: xPosition,
                    y: isBeingDragged ? dragOffset.height : 0
                )
                .zIndex(isBeingDragged ? 100 : 0)
                .gesture(
                    viewModel.currentTool == .blade ?
                        bladeTapGesture(for: clip, in: geometry) :
                        nil
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            if viewModel.currentTool == .select || viewModel.currentTool == .move || viewModel.currentTool == .trim {
                                viewModel.selectClip(clip)
                            }
                        }
                )
                .gesture(
                    viewModel.currentTool == .move ? dragGesture(for: clip) : nil
                )
                .simultaneousGesture(
                    viewModel.currentTool != .blade ?
                        trimGesture(for: clip, in: geometry) : nil
                )
        }
    }

    // MARK: - Legacy ClipView Fallback (kept for reference)
    // The old ForEach-based ClipView rendering has been replaced with Canvas

    private func dragGesture(for clip: VideoClip) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Capture original start time on first drag event
                if !isDragging {
                    dragOriginalStartTime = clip.cmTimelineStartTime
                    draggingClipId = clip.id
                }

                isDragging = true
                viewModel.selectClip(clip)

                // Update horizontal position (time)
                let newTime = timelineViewModel.time(
                    for: value.location.x - AppConstants.trackLabelWidth,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                )
                let clampedTime = max(newTime, CMTime.zero)
                clip.setTimelineStartTime(clampedTime)

                // Track vertical offset for visual feedback
                dragOffset = CGSize(width: 0, height: value.translation.height)
            }
            .onEnded { value in
                isDragging = false
                draggingClipId = nil

                // Capture the new start time before any layer changes
                let newStartTime = clip.cmTimelineStartTime

                // Check if we should move to a different layer
                if let targetLayer = viewModel.getVideoLayerAtOffset(
                    from: layer,
                    yOffset: value.translation.height,
                    trackHeight: trackHeight
                ), targetLayer.id != layer.id {
                    viewModel.moveClipToLayer(clip, from: layer, to: targetLayer)
                } else {
                    // Record move action for undo/redo
                    viewModel.recordMoveClip(clip, originalStartTime: dragOriginalStartTime, newStartTime: newStartTime)
                }

                dragOffset = .zero
                dragOriginalStartTime = .zero
            }
    }

    // MARK: - Transition Overlays

    @ViewBuilder
    private func transitionOverlays(in geometry: GeometryProxy) -> some View {
        let sortedClips = layer.sortedClips

        ForEach(Array(sortedClips.enumerated()), id: \.element.id) { index, clip in
            // Check if this clip has an outgoing transition
            if let transition = clip.outTransition,
               index + 1 < sortedClips.count {
                let toClip = sortedClips[index + 1]

                // Position transition at the junction between clips
                let transitionStart = CMTimeSubtract(clip.cmTimelineEndTime, transition.cmDuration)
                let xPosition = timelineViewModel.xPosition(
                    for: transitionStart,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth

                TransitionView(
                    transition: transition,
                    pixelsPerSecond: viewModel.pixelsPerSecond,
                    trackHeight: geometry.size.height - 8,
                    isSelected: false,
                    isTransitionToolActive: viewModel.currentTool == .transition
                )
                .offset(x: xPosition, y: 0)
                .zIndex(50)  // Above clips but below dragged clips
                .onTapGesture {
                    if viewModel.currentTool == .transition {
                        viewModel.handleTransitionBetweenClips(clip, toClip)
                    }
                }
            }
            // Show placeholder for adding transition (only when transition tool is active)
            else if viewModel.currentTool == .transition,
                    index + 1 < sortedClips.count {
                let toClip = sortedClips[index + 1]

                // Position placeholder at the junction
                let junctionTime = clip.cmTimelineEndTime
                let xPosition = timelineViewModel.xPosition(
                    for: junctionTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth - 12  // Center the placeholder

                TransitionPlaceholderView(
                    trackHeight: geometry.size.height - 8,
                    isHighlighted: true
                )
                .offset(x: xPosition, y: 0)
                .zIndex(50)
                .onTapGesture {
                    viewModel.handleTransitionBetweenClips(clip, toClip)
                }
            }
        }
    }

    private func bladeTapGesture(for clip: VideoClip, in geometry: GeometryProxy) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // Calculate the time from tap location relative to the clip
                let clipStartX = timelineViewModel.xPosition(
                    for: clip.cmTimelineStartTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth

                // Tap location relative to clip start
                let tapXInClip = value.location.x - clipStartX

                // Convert to time offset within the clip
                let timeOffset = timelineViewModel.time(
                    for: tapXInClip,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                )

                // Calculate absolute timeline time
                let splitTime = CMTimeAdd(clip.cmTimelineStartTime, timeOffset)

                // Split the clip at this time
                viewModel.splitClipAtTime(clip, at: splitTime)
            }
    }

    // MARK: - Trim Gesture

    private func trimGesture(for clip: VideoClip, in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let clipStartX = timelineViewModel.xPosition(
                    for: clip.cmTimelineStartTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth

                let clipWidth = CGFloat(clip.cmDuration.seconds) * viewModel.pixelsPerSecond
                let clipEndX = clipStartX + clipWidth

                // On first drag, determine which edge we're trimming
                if !isTrimming {
                    let startLocationX = value.startLocation.x

                    // Check if drag started near leading edge
                    if abs(startLocationX - clipStartX) < trimHandleHitWidth {
                        isTrimming = true
                        trimmingClipId = clip.id
                        trimEdge = .leading
                        trimStartX = value.startLocation.x
                        trimOriginalSourceStart = clip.cmSourceStartTime
                        trimOriginalTimelineStart = clip.cmTimelineStartTime
                        trimOriginalDuration = clip.cmDuration
                        // Capture before snapshot for undo
                        trimBeforeSnapshot = VideoClipTimingSnapshot(from: clip)
                        viewModel.selectClip(clip)
                    }
                    // Check if drag started near trailing edge
                    else if abs(startLocationX - clipEndX) < trimHandleHitWidth {
                        isTrimming = true
                        trimmingClipId = clip.id
                        trimEdge = .trailing
                        trimStartX = value.startLocation.x
                        trimOriginalSourceStart = clip.cmSourceStartTime
                        trimOriginalTimelineStart = clip.cmTimelineStartTime
                        trimOriginalDuration = clip.cmDuration
                        // Capture before snapshot for undo
                        trimBeforeSnapshot = VideoClipTimingSnapshot(from: clip)
                        viewModel.selectClip(clip)
                    }
                }

                // Apply trim based on drag
                if isTrimming {
                    let deltaX = value.location.x - trimStartX
                    let deltaTime = timelineViewModel.time(
                        for: abs(deltaX),
                        pixelsPerSecond: viewModel.pixelsPerSecond
                    )

                    if trimEdge == .leading {
                        handleLeadingEdgeTrim(clip: clip, deltaX: deltaX, deltaTime: deltaTime)
                    } else if trimEdge == .trailing {
                        handleTrailingEdgeTrim(clip: clip, deltaX: deltaX, deltaTime: deltaTime)
                    }
                }
            }
            .onEnded { _ in
                if isTrimming {
                    // Capture after snapshot and record trim action
                    if let beforeSnapshot = trimBeforeSnapshot {
                        let afterSnapshot = VideoClipTimingSnapshot(from: clip)
                        viewModel.recordTrimClip(clip, beforeSnapshot: beforeSnapshot, afterSnapshot: afterSnapshot)
                    }
                }

                // Reset trim state
                isTrimming = false
                trimmingClipId = nil
                trimEdge = nil
                trimBeforeSnapshot = nil
            }
    }

    private var project: Project {
        viewModel.project
    }

    /// Handle trimming from the leading (left) edge
    private func handleLeadingEdgeTrim(clip: VideoClip, deltaX: CGFloat, deltaTime: CMTime) {
        // Minimum clip duration (0.1 seconds)
        let minDuration = CMTime(seconds: 0.1, preferredTimescale: 600)

        if deltaX > 0 {
            // Dragging right - make clip shorter from start (trim in)
            // Increase sourceStartTime, increase timelineStartTime, decrease duration
            let newSourceStart = CMTimeAdd(trimOriginalSourceStart, deltaTime)
            let newTimelineStart = CMTimeAdd(trimOriginalTimelineStart, deltaTime)
            let newDuration = CMTimeSubtract(trimOriginalDuration, deltaTime)

            // Don't trim past minimum duration
            if CMTimeCompare(newDuration, minDuration) >= 0 {
                // Don't exceed original media bounds
                let maxSourceStart = CMTimeSubtract(clip.cmOriginalDuration, minDuration)
                if CMTimeCompare(newSourceStart, maxSourceStart) <= 0 {
                    clip.setSourceStartTime(newSourceStart)
                    clip.setTimelineStartTime(newTimelineStart)
                    clip.setDuration(newDuration)
                }
            }
        } else {
            // Dragging left - make clip longer from start (extend)
            // Decrease sourceStartTime, decrease timelineStartTime, increase duration
            let newSourceStart = CMTimeSubtract(trimOriginalSourceStart, deltaTime)
            let newTimelineStart = CMTimeSubtract(trimOriginalTimelineStart, deltaTime)
            let newDuration = CMTimeAdd(trimOriginalDuration, deltaTime)

            // Don't extend past beginning of source media
            if CMTimeCompare(newSourceStart, .zero) >= 0 {
                // Don't extend past timeline start (prevent negative timeline position)
                if CMTimeCompare(newTimelineStart, .zero) >= 0 {
                    clip.setSourceStartTime(newSourceStart)
                    clip.setTimelineStartTime(newTimelineStart)
                    clip.setDuration(newDuration)
                } else {
                    // Clamp to timeline start
                    let availableExtension = trimOriginalTimelineStart
                    let clampedSourceStart = CMTimeSubtract(trimOriginalSourceStart, availableExtension)
                    let clampedDuration = CMTimeAdd(trimOriginalDuration, availableExtension)

                    if CMTimeCompare(clampedSourceStart, .zero) >= 0 {
                        clip.setSourceStartTime(clampedSourceStart)
                        clip.setTimelineStartTime(.zero)
                        clip.setDuration(clampedDuration)
                    }
                }
            }
        }
    }

    /// Handle trimming from the trailing (right) edge
    private func handleTrailingEdgeTrim(clip: VideoClip, deltaX: CGFloat, deltaTime: CMTime) {
        // Minimum clip duration (0.1 seconds)
        let minDuration = CMTime(seconds: 0.1, preferredTimescale: 600)

        if deltaX < 0 {
            // Dragging left - make clip shorter from end (trim out)
            let newDuration = CMTimeSubtract(trimOriginalDuration, deltaTime)

            // Don't trim below minimum duration
            if CMTimeCompare(newDuration, minDuration) >= 0 {
                clip.setDuration(newDuration)
            }
        } else {
            // Dragging right - make clip longer from end (extend)
            let newDuration = CMTimeAdd(trimOriginalDuration, deltaTime)

            // Don't extend past original media bounds
            let maxDuration = CMTimeSubtract(clip.cmOriginalDuration, clip.cmSourceStartTime)
            if CMTimeCompare(newDuration, maxDuration) <= 0 {
                clip.setDuration(newDuration)
            }
        }
    }
}

#Preview {
    VideoTrackView(
        layer: VideoLayer(name: "V1", zIndex: 0),
        viewModel: EditorViewModel(project: Project(name: "Test")),
        timelineViewModel: TimelineViewModel(),
        trackHeight: 60
    )
    .frame(height: 60)
}
