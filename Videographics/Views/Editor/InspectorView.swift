//
//  InspectorView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct InspectorView: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let clip = viewModel.selectedClip {
                ScrollView {
                    VStack(spacing: 20) {
                        // Timing Section
                        InspectorSection(title: "Timing") {
                            TimingRow(label: "Start", time: clip.cmTimelineStartTime)
                            TimingRow(label: "Duration", time: clip.cmDuration)
                            TimingRow(label: "End", time: clip.cmTimelineEndTime)

                            Divider()

                            TimingRow(label: "Source In", time: clip.cmSourceStartTime)
                            TimingRow(label: "Original Duration", time: clip.cmOriginalDuration)
                        }

                        // Volume Section
                        InspectorSection(title: "Audio") {
                            VolumeControl(volume: Binding(
                                get: { clip.volume },
                                set: { newValue in
                                    clip.volume = newValue
                                    viewModel.project.modifiedAt = Date()
                                    Task {
                                        await viewModel.rebuildComposition()
                                    }
                                }
                            ))
                        }

                        // Transform Section (Video only)
                        InspectorSection(title: "Transform") {
                            ScaleModeRow(
                                scaleMode: clip.scaleMode,
                                onSelect: { mode in
                                    viewModel.setScaleMode(mode)
                                }
                            )

                            ScaleRow(
                                label: "Scale",
                                value: Binding(
                                    get: { clip.scale },
                                    set: { newValue in
                                        clip.scale = newValue
                                        viewModel.project.modifiedAt = Date()
                                        Task {
                                            await viewModel.rebuildComposition()
                                        }
                                    }
                                ),
                                range: 0.1...3.0
                            )

                            PositionRow(
                                label: "Position X",
                                value: Binding(
                                    get: { clip.positionX },
                                    set: { newValue in
                                        clip.positionX = newValue
                                        viewModel.project.modifiedAt = Date()
                                        Task {
                                            await viewModel.rebuildComposition()
                                        }
                                    }
                                )
                            )

                            PositionRow(
                                label: "Position Y",
                                value: Binding(
                                    get: { clip.positionY },
                                    set: { newValue in
                                        clip.positionY = newValue
                                        viewModel.project.modifiedAt = Date()
                                        Task {
                                            await viewModel.rebuildComposition()
                                        }
                                    }
                                )
                            )

                            Button("Reset Transform") {
                                clip.scale = 1.0
                                clip.positionX = 0.0
                                clip.positionY = 0.0
                                viewModel.project.modifiedAt = Date()
                                Task {
                                    await viewModel.rebuildComposition()
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.blue)
                        }

                        // Source Info Section
                        InspectorSection(title: "Source") {
                            SourceInfoRow(label: "Resolution", value: "\(clip.sourceWidth) × \(clip.sourceHeight)")

                            if let url = clip.assetURL {
                                SourceInfoRow(label: "File", value: url.lastPathComponent)
                            }
                        }

                        // Quick Actions Section
                        InspectorSection(title: "Actions") {
                            HStack(spacing: 12) {
                                ActionButton(
                                    icon: "doc.on.doc",
                                    label: "Duplicate",
                                    action: {
                                        viewModel.duplicateSelectedClip()
                                        dismiss()
                                    }
                                )

                                ActionButton(
                                    icon: "scissors",
                                    label: "Split",
                                    action: {
                                        dismiss()
                                        viewModel.currentTool = .blade
                                        // Move playhead to middle of clip for split
                                        let midTime = CMTimeAdd(
                                            clip.cmTimelineStartTime,
                                            CMTimeMultiplyByFloat64(clip.cmDuration, multiplier: 0.5)
                                        )
                                        viewModel.splitClipAtTime(clip, at: midTime)
                                    }
                                )

                                ActionButton(
                                    icon: "trash",
                                    label: "Delete",
                                    isDestructive: true,
                                    action: {
                                        viewModel.deleteSelectedClip()
                                        dismiss()
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Clip Inspector")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Clip Selected",
                    systemImage: "film",
                    description: Text("Select a clip on the timeline to view its properties")
                )
                .navigationTitle("Inspector")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Section Container

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                content
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Timing Row

struct TimingRow: View {
    let label: String
    let time: CMTime

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatTime(time))
                .font(.system(.body, design: .monospaced))
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds.isFinite else { return "0:00:00" }

        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)

        return String(format: "%d:%02d:%02d", minutes, secs, frames)
    }
}

// MARK: - Volume Control

struct VolumeControl: View {
    @Binding var volume: Float

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }

            Text("\(Int(volume * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Scale Mode Row

struct ScaleModeRow: View {
    let scaleMode: VideoScaleMode
    let onSelect: (VideoScaleMode) -> Void

    var body: some View {
        HStack {
            Text("Scale Mode")
                .foregroundStyle(.secondary)
            Spacer()

            Menu {
                ForEach(VideoScaleMode.allCases, id: \.self) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if scaleMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(scaleMode.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Scale Row

struct ScaleRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(.body, design: .monospaced))
            }

            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Position Row

struct PositionRow: View {
    let label: String
    @Binding var value: Float

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(.body, design: .monospaced))
            }

            Slider(value: $value, in: -1...1)
        }
    }
}

// MARK: - Source Info Row

struct SourceInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isDestructive ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
            .foregroundStyle(isDestructive ? .red : .blue)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    InspectorView(viewModel: EditorViewModel(project: Project(name: "Test")))
}
