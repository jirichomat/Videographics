//
//  TransitionSheet.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct TransitionSheet: View {
    @Bindable var viewModel: EditorViewModel
    @State private var selectedType: TransitionType = .crossDissolve
    @State private var durationSeconds: Double = 0.5

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundStyle(.purple)

                    Text("Add Transition")
                        .font(.title2.bold())

                    if viewModel.pendingTransitionFromClip != nil,
                       viewModel.pendingTransitionToClip != nil {
                        Text("Between clips")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                // Transition type picker
                transitionTypePicker

                // Duration control
                durationControl

                // Preview section
                previewSection

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        viewModel.confirmTransition(type: selectedType, duration: durationSeconds)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Transition")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Remove transition button (if editing existing)
                    if viewModel.pendingTransitionFromClip?.outTransition != nil {
                        Button(role: .destructive) {
                            viewModel.removeTransition()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove Transition")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Button {
                        viewModel.cancelTransition()
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
        .onAppear {
            // Load existing transition settings if editing
            if let existingTransition = viewModel.pendingTransitionFromClip?.outTransition {
                selectedType = existingTransition.type
                durationSeconds = existingTransition.durationSeconds
            } else {
                selectedType = .crossDissolve
                durationSeconds = selectedType.defaultDuration
            }
        }
        .onChange(of: selectedType) { _, newType in
            // Update duration to default when type changes (unless user has customized)
            durationSeconds = newType.defaultDuration
        }
    }

    // MARK: - Transition Type Picker

    @ViewBuilder
    private var transitionTypePicker: some View {
        VStack(spacing: 12) {
            Text("Transition Type")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(TransitionType.allCases) { type in
                    transitionTypeButton(type)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func transitionTypeButton(_ type: TransitionType) -> some View {
        let isSelected = selectedType == type

        Button {
            selectedType = type
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(type.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? Color.purple : Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duration Control

    @ViewBuilder
    private var durationControl: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Duration")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(String(format: "%.2fs", durationSeconds))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }

            // Preset buttons
            HStack(spacing: 8) {
                ForEach(Transition.durationPresets, id: \.seconds) { preset in
                    Button {
                        durationSeconds = preset.seconds
                    } label: {
                        Text(preset.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                abs(durationSeconds - preset.seconds) < 0.01
                                    ? Color.purple
                                    : Color(.tertiarySystemGroupedBackground)
                            )
                            .foregroundStyle(
                                abs(durationSeconds - preset.seconds) < 0.01
                                    ? .white
                                    : .primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Slider for fine control
            Slider(
                value: $durationSeconds,
                in: Transition.minDuration...Transition.maxDuration,
                step: 0.05
            )
            .tint(.purple)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        VStack(spacing: 12) {
            Text("Preview")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                // From clip thumbnail
                clipPreview(
                    label: "From",
                    imageData: viewModel.transitionFromFrameData,
                    isLoading: viewModel.isLoadingTransitionFrames
                )

                // Transition indicator
                VStack(spacing: 4) {
                    Image(systemName: selectedType.icon)
                        .font(.title3)
                        .foregroundStyle(.purple)

                    Text(String(format: "%.1fs", durationSeconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 50)

                // To clip thumbnail
                clipPreview(
                    label: "To",
                    imageData: viewModel.transitionToFrameData,
                    isLoading: viewModel.isLoadingTransitionFrames
                )
            }
            .frame(height: 80)

            // Transition description
            Text(selectedType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func clipPreview(label: String, imageData: Data?, isLoading: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if isLoading {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.tertiarySystemGroupedBackground))
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let data = imageData,
                          let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.tertiarySystemGroupedBackground))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 60)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TransitionSheet(viewModel: EditorViewModel(project: Project(name: "Test")))
}
