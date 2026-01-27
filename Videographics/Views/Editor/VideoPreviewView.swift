//
//  VideoPreviewView.swift
//  Videographics
//

import SwiftUI
import AVKit

struct VideoPreviewView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let player = viewModel.player, viewModel.playerItem != nil {
                    // Video player
                    VideoPlayer(player: player)
                        .aspectRatio(AppConstants.defaultAspectRatio, contentMode: .fit)
                        .disabled(true) // Disable built-in controls
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)

                        Text("Add a video to get started")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button {
                            viewModel.showingMediaPicker = true
                        } label: {
                            Label("Import Video", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Time overlay
                VStack {
                    Spacer()
                    HStack {
                        // Play/Pause button
                        Button {
                            viewModel.togglePlayback()
                        } label: {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        Spacer()

                        // Time display
                        Text(viewModel.formattedCurrentTime)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding()
                }
            }
        }
    }
}

#Preview {
    VideoPreviewView(viewModel: EditorViewModel(project: Project(name: "Test")))
        .frame(height: 400)
}
