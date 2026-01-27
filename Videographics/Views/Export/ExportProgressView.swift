//
//  ExportProgressView.swift
//  Videographics
//

import SwiftUI

struct ExportProgressView: View {
    let state: ExportState
    let onCancel: () -> Void
    let onDone: () -> Void
    let onSaveToPhotos: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Status icon
            statusIcon
                .font(.system(size: 60))
                .foregroundStyle(iconColor)

            // Status text
            Text(statusTitle)
                .font(.headline)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Progress bar (when exporting)
            if case .exporting(let progress) = state {
                VStack(spacing: 8) {
                    ProgressView(value: Double(progress))
                        .progressViewStyle(.linear)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }

            // Loading indicator (when preparing or saving)
            if state == .preparing || state == .saving {
                ProgressView()
                    .scaleEffect(1.2)
            }

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "square.and.arrow.up")
        case .preparing:
            Image(systemName: "gearshape")
        case .exporting:
            Image(systemName: "film")
        case .saving:
            Image(systemName: "arrow.down.circle")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        }
    }

    private var iconColor: Color {
        switch state {
        case .completed:
            return .green
        case .failed:
            return .red
        default:
            return .accentColor
        }
    }

    private var statusTitle: String {
        switch state {
        case .idle:
            return "Ready to Export"
        case .preparing:
            return "Preparing..."
        case .exporting:
            return "Exporting..."
        case .saving:
            return "Saving..."
        case .completed:
            return "Export Complete"
        case .failed:
            return "Export Failed"
        }
    }

    private var statusMessage: String {
        switch state {
        case .idle:
            return "Your video will be rendered with your selected settings."
        case .preparing:
            return "Building your video composition..."
        case .exporting(let progress):
            return "Rendering video... \(Int(progress * 100))% complete"
        case .saving:
            return "Saving to Photo Library..."
        case .completed:
            return "Your video has been exported successfully."
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch state {
        case .idle:
            EmptyView()

        case .preparing, .exporting, .saving:
            Button(role: .cancel) {
                onCancel()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

        case .completed:
            VStack(spacing: 12) {
                Button {
                    onSaveToPhotos()
                } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

        case .failed:
            Button {
                onDone()
            } label: {
                Text("Close")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    ExportProgressView(
        state: .exporting(progress: 0.45),
        onCancel: {},
        onDone: {},
        onSaveToPhotos: {}
    )
}
