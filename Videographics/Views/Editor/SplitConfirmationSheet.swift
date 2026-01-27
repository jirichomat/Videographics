//
//  SplitConfirmationSheet.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct SplitConfirmationSheet: View {
    @Bindable var viewModel: EditorViewModel
    @State private var expandedFrame: ExpandedFrame?

    enum ExpandedFrame: Identifiable {
        case before, after
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)

                    Text("Split Clip")
                        .font(.title2.bold())
                }
                .padding(.top, 8)

                // Frame preview section
                if let clip = viewModel.pendingSplitClip,
                   let splitInfo = viewModel.pendingSplitInfo {
                    framePreviewSection(clip: clip, splitInfo: splitInfo)
                }

                // Fine-tune controls
                fineTuneControls

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        viewModel.confirmSplit()
                    } label: {
                        HStack {
                            Image(systemName: "scissors")
                            Text("Split Here")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.cancelSplit()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.bottom)
            }
            .padding(.horizontal)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $expandedFrame) { frame in
            expandedFrameView(frame: frame)
        }
    }

    // MARK: - Expanded Frame View

    @ViewBuilder
    private func expandedFrameView(frame: ExpandedFrame) -> some View {
        let imageData = frame == .before ? viewModel.splitFrameBeforeData : viewModel.splitFrameAfterData
        let title = frame == .before ? "End of Part 1" : "Start of Part 2"

        ZStack {
            Color.black.ignoresSafeArea()

            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button {
                        expandedFrame = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()

                    Spacer()

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    // Balance spacer
                    Color.clear.frame(width: 44, height: 44)
                        .padding()
                }
                .background(.ultraThinMaterial.opacity(0.5))

                Spacer()
            }
        }
        .onTapGesture {
            expandedFrame = nil
        }
    }

    // MARK: - Frame Preview Section

    @ViewBuilder
    private func framePreviewSection(clip: VideoClip, splitInfo: (firstDuration: CMTime, secondDuration: CMTime, splitOffsetInClip: CMTime)) -> some View {
        VStack(spacing: 12) {
            // Split position indicator
            HStack {
                Text("Split at:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(viewModel.pendingSplitTime))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }

            // Side-by-side frame preview
            HStack(spacing: 4) {
                // Last frame of Part 1
                framePreview(
                    label: "End of Part 1",
                    duration: splitInfo.firstDuration,
                    imageData: viewModel.splitFrameBeforeData,
                    isLoading: viewModel.isLoadingSplitFrames,
                    alignment: .trailing
                )
                .onTapGesture {
                    if viewModel.splitFrameBeforeData != nil {
                        expandedFrame = .before
                    }
                }

                // Split line
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 3)

                    Image(systemName: "scissors")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .rotationEffect(.degrees(-90))

                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 3)
                }
                .frame(width: 24)

                // First frame of Part 2
                framePreview(
                    label: "Start of Part 2",
                    duration: splitInfo.secondDuration,
                    imageData: viewModel.splitFrameAfterData,
                    isLoading: viewModel.isLoadingSplitFrames,
                    alignment: .leading
                )
                .onTapGesture {
                    if viewModel.splitFrameAfterData != nil {
                        expandedFrame = .after
                    }
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func framePreview(label: String, duration: CMTime, imageData: Data?, isLoading: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            // Frame thumbnail
            ZStack {
                if isLoading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemGroupedBackground))
                    ProgressView()
                } else if let data = imageData,
                          let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(4)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemGroupedBackground))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)

            // Label
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatDuration(duration))
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Fine-tune Controls

    @ViewBuilder
    private var fineTuneControls: some View {
        VStack(spacing: 12) {
            Text("Fine-tune Split Point")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            // Frame stepping controls
            HStack(spacing: 16) {
                // Jump backward
                Button {
                    viewModel.adjustSplitTime(frames: -10)
                } label: {
                    Label("-10", systemImage: "chevron.backward.2")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                // Step backward
                Button {
                    viewModel.adjustSplitTime(frames: -1)
                } label: {
                    Label("-1", systemImage: "chevron.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Frame")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Step forward
                Button {
                    viewModel.adjustSplitTime(frames: 1)
                } label: {
                    Label("+1", systemImage: "chevron.forward")
                        .font(.caption)
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.bordered)

                // Jump forward
                Button {
                    viewModel.adjustSplitTime(frames: 10)
                } label: {
                    Label("+10", systemImage: "chevron.forward.2")
                        .font(.caption)
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.bordered)
            }

            // Fine millisecond controls
            HStack(spacing: 16) {
                Button {
                    viewModel.adjustSplitTimeMs(milliseconds: -100)
                } label: {
                    Text("-100ms")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Spacer()

                Text("Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    viewModel.adjustSplitTimeMs(milliseconds: 100)
                } label: {
                    Text("+100ms")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func formatTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds.isFinite else { return "0:00:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", minutes, secs, frames)
    }

    private func formatDuration(_ time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds.isFinite else { return "0.0s" }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds) / 60
            let secs = seconds.truncatingRemainder(dividingBy: 60)
            return String(format: "%dm %.1fs", minutes, secs)
        }
    }
}

// MARK: - Trailing Icon Label Style

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    SplitConfirmationSheet(viewModel: EditorViewModel(project: Project(name: "Test")))
}
