//
//  TimelineContainerView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct TimelineContainerView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var timelineViewModel = TimelineViewModel()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Time Ruler - tap to move playhead
                TimeRulerView(
                    pixelsPerSecond: viewModel.pixelsPerSecond,
                    scrollOffset: timelineViewModel.scrollOffset,
                    totalDuration: viewModel.project.timeline?.duration ?? .zero,
                    onSeek: { time in
                        viewModel.seek(to: time)
                    }
                )
                .frame(height: AppConstants.timeRulerHeight)

                Divider()

                // Scrollable timeline content
                // Disable scrolling when Move tool is active to prevent interference with clip dragging
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Layer stack
                        LayerStackView(
                            viewModel: viewModel,
                            timelineViewModel: timelineViewModel
                        )

                        // Playhead
                        PlayheadView(
                            currentTime: viewModel.currentTime,
                            pixelsPerSecond: viewModel.pixelsPerSecond,
                            height: timelineHeight
                        )
                    }
                    .frame(
                        minWidth: timelineViewModel.timelineWidth(
                            for: viewModel.project.timeline?.duration ?? .zero,
                            pixelsPerSecond: viewModel.pixelsPerSecond,
                            minWidth: geometry.size.width
                        )
                    )
                }
                .scrollDisabled(viewModel.currentTool == .move || viewModel.currentTool == .trim)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private var timelineHeight: CGFloat {
        let videoLayerCount = CGFloat(viewModel.project.timeline?.videoLayers.count ?? 1)
        let audioLayerCount = CGFloat(viewModel.project.timeline?.audioLayers.count ?? 1)

        return (videoLayerCount * AppConstants.videoTrackHeight) +
               (audioLayerCount * AppConstants.audioTrackHeight) +
               16 // Padding
    }
}

#Preview {
    TimelineContainerView(viewModel: EditorViewModel(project: Project(name: "Test")))
        .frame(height: 200)
}
