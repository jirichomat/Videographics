//
//  AudioTrackView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct AudioTrackView: View {
    let layer: AudioLayer
    @Bindable var viewModel: EditorViewModel
    let timelineViewModel: TimelineViewModel
    var scrollOffset: CGFloat = 0
    var visibleWidth: CGFloat = 800

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

                // Canvas-based audio clip rendering (high performance)
                canvasAudioClipLayer(in: geometry)

                // Gesture overlay layer (for future audio clip interactions)
                gestureOverlayLayer(in: geometry)

                // Track label (rendered last so it appears on top of clips)
                HStack(spacing: 2) {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(layer.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: AppConstants.trackLabelWidth, height: geometry.size.height)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    // MARK: - Canvas Audio Clip Rendering

    @ViewBuilder
    private func canvasAudioClipLayer(in geometry: GeometryProxy) -> some View {
        let clipRenderInfos = layer.clips.map { clip -> AudioClipRenderInfo in
            AudioClipRenderInfo(
                clip: clip,
                xPosition: timelineViewModel.xPosition(
                    for: clip.cmTimelineStartTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond
                ) + AppConstants.trackLabelWidth,
                pixelsPerSecond: viewModel.pixelsPerSecond,
                isSelected: false  // Audio clips don't have selection yet
            )
        }

        CanvasAudioRenderer(
            clips: clipRenderInfos,
            trackHeight: geometry.size.height,
            visibleRange: visibleRange
        )
    }

    // MARK: - Gesture Overlay Layer

    @ViewBuilder
    private func gestureOverlayLayer(in geometry: GeometryProxy) -> some View {
        ForEach(layer.clips) { clip in
            let clipWidth = CGFloat(clip.cmDuration.seconds) * viewModel.pixelsPerSecond
            let xPosition = timelineViewModel.xPosition(
                for: clip.cmTimelineStartTime,
                pixelsPerSecond: viewModel.pixelsPerSecond
            ) + AppConstants.trackLabelWidth

            // Transparent hit area for gestures (future audio clip interactions)
            Color.clear
                .frame(width: clipWidth, height: geometry.size.height - 8)
                .contentShape(Rectangle())
                .offset(x: xPosition)
        }
    }
}

// Legacy AudioClipView kept for compatibility (no longer used in main rendering)
struct AudioClipView: View {
    let clip: AudioClip
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.green.opacity(0.6))
            .frame(
                width: CGFloat(clip.cmDuration.seconds) * pixelsPerSecond,
                height: trackHeight
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.green, lineWidth: 1)
            )
    }
}

#Preview {
    AudioTrackView(
        layer: AudioLayer(name: "Audio", zIndex: -1),
        viewModel: EditorViewModel(project: Project(name: "Test")),
        timelineViewModel: TimelineViewModel()
    )
    .frame(height: 40)
}
