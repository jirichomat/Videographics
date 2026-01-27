//
//  ExportSheet.swift
//  Videographics
//

import SwiftUI

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let timeline: Timeline
    let projectId: UUID
    let onExportComplete: (URL) -> Void

    @StateObject private var exportService = ExportService.shared

    @State private var selectedPlatform: ExportPlatform = .tiktok
    @State private var selectedQuality: ExportQuality = .high
    @State private var showingProgress = false
    @State private var exportedURL: URL?
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Group {
                if showingProgress {
                    ExportProgressView(
                        state: exportService.exportState,
                        onCancel: cancelExport,
                        onDone: {
                            exportService.reset()
                            dismiss()
                        },
                        onSaveToPhotos: saveToPhotoLibrary
                    )
                } else {
                    presetSelectionView
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !showingProgress {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var presetSelectionView: some View {
        List {
            // Platform selection
            Section {
                ForEach(ExportPlatform.allCases) { platform in
                    PlatformRow(
                        platform: platform,
                        isSelected: selectedPlatform == platform
                    ) {
                        selectedPlatform = platform
                        validateSelection()
                    }
                }
            } header: {
                Text("Platform")
            } footer: {
                if let maxDuration = selectedPlatform.maxDurationDescription {
                    Text("Maximum duration: \(maxDuration)")
                }
            }

            // Quality selection
            Section("Quality") {
                Picker("Quality", selection: $selectedQuality) {
                    ForEach(ExportQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Video info
            Section("Export Settings") {
                LabeledContent("Resolution") {
                    Text(ExportPreset.preset(for: selectedPlatform).resolutionDescription)
                }
                LabeledContent("Frame Rate") {
                    Text("30 fps")
                }
                LabeledContent("Format") {
                    Text("MP4 (H.264)")
                }
            }

            // Validation error
            if let error = validationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            // Export button
            Section {
                Button {
                    startExport()
                } label: {
                    HStack {
                        Spacer()
                        Label("Export Video", systemImage: "square.and.arrow.up")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(validationError != nil)
            }
        }
    }

    private func validateSelection() {
        let preset = ExportPreset.preset(for: selectedPlatform)
        let result = ExportService.validateDuration(timeline: timeline, preset: preset)
        validationError = result.message
    }

    private func startExport() {
        showingProgress = true

        var preset = ExportPreset.preset(for: selectedPlatform)
        preset.quality = selectedQuality

        Task {
            do {
                let url = try await exportService.export(
                    timeline: timeline,
                    preset: preset,
                    projectId: projectId
                )
                exportedURL = url
                onExportComplete(url)
            } catch {
                // Error is handled by exportService.exportState
            }
        }
    }

    private func cancelExport() {
        exportService.cancelExport()
        showingProgress = false
    }

    private func saveToPhotoLibrary() {
        guard let url = exportedURL else { return }

        Task {
            do {
                try await PhotoLibraryService.shared.saveToPhotoLibrary(url: url)
                exportService.reset()
                dismiss()
            } catch {
                // Handle error - could show alert
            }
        }
    }
}

// MARK: - Platform Row

private struct PlatformRow: View {
    let platform: ExportPlatform
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                Image(systemName: platform.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.rawValue)
                        .foregroundStyle(.primary)

                    if let maxDuration = platform.maxDurationDescription {
                        Text("Max \(maxDuration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExportSheet(
        timeline: Timeline(),
        projectId: UUID(),
        onExportComplete: { _ in }
    )
}
