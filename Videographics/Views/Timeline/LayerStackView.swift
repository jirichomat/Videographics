//
//  LayerStackView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct LayerStackView: View {
    @Bindable var viewModel: EditorViewModel
    let timelineViewModel: TimelineViewModel

    @State private var prefetchTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let visibleFrame = geometry.frame(in: .global)
            let visibleWidth = geometry.size.width

            VStack(spacing: 0) {
                // Video layers (in reverse z-order so higher layers appear on top visually)
                if let timeline = viewModel.project.timeline {
                    ForEach(timeline.videoLayers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                        VideoTrackView(
                            layer: layer,
                            viewModel: viewModel,
                            timelineViewModel: timelineViewModel,
                            trackHeight: AppConstants.videoTrackHeight,
                            scrollOffset: timelineViewModel.scrollOffset,
                            visibleWidth: visibleWidth
                        )
                        .frame(height: AppConstants.videoTrackHeight)
                    }

                    // Audio layers
                    ForEach(timeline.audioLayers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                        AudioTrackView(
                            layer: layer,
                            viewModel: viewModel,
                            timelineViewModel: timelineViewModel,
                            scrollOffset: timelineViewModel.scrollOffset,
                            visibleWidth: visibleWidth
                        )
                        .frame(height: AppConstants.audioTrackHeight)
                    }
                }
            }
            .padding(.vertical, 8)
            .onChange(of: visibleFrame) { _, newFrame in
                prefetchNearbyThumbnails(visibleFrame: newFrame)
            }
            .onAppear {
                prefetchNearbyThumbnails(visibleFrame: visibleFrame)
            }
        }
    }

    /// Prefetch thumbnails for clips near the visible area
    private func prefetchNearbyThumbnails(visibleFrame: CGRect) {
        prefetchTask?.cancel()

        prefetchTask = Task { @MainActor in
            guard let timeline = viewModel.project.timeline else { return }

            // Calculate visible time range with buffer for prefetching
            let bufferPixels: CGFloat = 500 // Prefetch 500px ahead
            let visibleStartX = max(0, visibleFrame.minX - bufferPixels - AppConstants.trackLabelWidth)
            let visibleEndX = visibleFrame.maxX + bufferPixels

            let visibleStartTime = timelineViewModel.time(
                for: visibleStartX,
                pixelsPerSecond: viewModel.pixelsPerSecond
            )
            let visibleEndTime = timelineViewModel.time(
                for: visibleEndX,
                pixelsPerSecond: viewModel.pixelsPerSecond
            )

            // Collect clips that are within or near the visible range
            var clipsToFetch: [VideoClip] = []

            for layer in timeline.videoLayers {
                for clip in layer.clips {
                    // Check if clip overlaps with visible time range
                    let clipStart = clip.cmTimelineStartTime
                    let clipEnd = clip.cmTimelineEndTime

                    if clipEnd.seconds >= visibleStartTime.seconds &&
                       clipStart.seconds <= visibleEndTime.seconds {
                        clipsToFetch.append(clip)
                    }
                }
            }

            // Prefetch thumbnails for these clips
            if !clipsToFetch.isEmpty {
                ThumbnailCache.shared.prefetchThumbnails(for: clipsToFetch)
            }
        }
    }
}

#Preview {
    LayerStackView(
        viewModel: EditorViewModel(project: Project(name: "Test")),
        timelineViewModel: TimelineViewModel()
    )
    .frame(height: 150)
}
