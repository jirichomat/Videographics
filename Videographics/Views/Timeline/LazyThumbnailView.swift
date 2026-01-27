//
//  LazyThumbnailView.swift
//  Videographics
//
//  Displays thumbnails with lazy loading based on visibility

import SwiftUI
import CoreMedia

/// A view that lazily loads and displays thumbnails for a video clip
struct LazyThumbnailView: View {
    let clip: VideoClip
    let clipWidth: CGFloat
    let trackHeight: CGFloat

    @State private var loadedImages: [Int: UIImage] = [:]
    @State private var isVisible: Bool = false
    @State private var loadTask: Task<Void, Never>?

    private var thumbnailCache: ThumbnailCache {
        ThumbnailCache.shared
    }

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)

            HStack(spacing: 0) {
                let thumbnailsData = clip.thumbnails

                if !thumbnailsData.isEmpty {
                    ForEach(0..<thumbnailsData.count, id: \.self) { index in
                        thumbnailImage(at: index)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                } else {
                    // Fallback gradient when no thumbnails
                    LinearGradient(
                        colors: [.blue.opacity(0.4), .blue.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .onChange(of: frame) { oldFrame, newFrame in
                updateVisibility(frame: newFrame, in: geometry)
            }
            .onAppear {
                updateVisibility(frame: frame, in: geometry)
                loadVisibleThumbnails()
            }
            .onDisappear {
                handleDisappear()
            }
        }
        .frame(width: clipWidth, height: trackHeight)
    }

    @ViewBuilder
    private func thumbnailImage(at index: Int) -> some View {
        if let image = loadedImages[index] {
            // Use cached image
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Placeholder while loading
            Rectangle()
                .fill(Color.blue.opacity(0.2))
                .overlay(
                    ProgressView()
                        .scaleEffect(0.5)
                        .opacity(isVisible ? 1 : 0)
                )
        }
    }

    private func updateVisibility(frame: CGRect, in geometry: GeometryProxy) {
        // Check if the clip is visible in the viewport
        // Use the geometry's global frame to determine the container bounds
        let containerFrame = geometry.frame(in: .global)
        let buffer: CGFloat = 200 // Prefetch buffer

        // Assume reasonable screen width based on container or fallback
        let estimatedScreenWidth = max(containerFrame.width, 400)

        let wasVisible = isVisible
        isVisible = frame.maxX > -buffer && frame.minX < estimatedScreenWidth + buffer

        if isVisible && !wasVisible {
            // Became visible - load thumbnails
            thumbnailCache.markClipVisible(clip.id)
            loadVisibleThumbnails()
        } else if !isVisible && wasVisible {
            // Became hidden - mark as hidden
            thumbnailCache.markClipHidden(clip.id)
        }
    }

    private func loadVisibleThumbnails() {
        // Cancel any existing load task
        loadTask?.cancel()

        loadTask = Task { @MainActor in
            let thumbnailsData = clip.thumbnails
            guard !thumbnailsData.isEmpty else { return }

            // First, check cache for already loaded thumbnails
            for index in 0..<thumbnailsData.count {
                if Task.isCancelled { return }

                if let cached = thumbnailCache.getThumbnail(for: clip.id, at: index) {
                    loadedImages[index] = cached
                }
            }

            // Then load any missing thumbnails
            for index in 0..<thumbnailsData.count {
                if Task.isCancelled { return }

                // Skip if already loaded
                if loadedImages[index] != nil { continue }

                // Decode the image
                let data = thumbnailsData[index]
                if let image = await decodeImage(from: data) {
                    if Task.isCancelled { return }

                    // Cache and display
                    thumbnailCache.setThumbnail(image, for: clip.id, at: index)
                    loadedImages[index] = image
                }
            }
        }
    }

    private func handleDisappear() {
        // Cancel loading if view disappears
        loadTask?.cancel()
        loadTask = nil

        // Mark clip as hidden
        thumbnailCache.markClipHidden(clip.id)

        // Clear local state (cache retains the images)
        loadedImages.removeAll()
    }

    private func decodeImage(from data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = UIImage(data: data)
                continuation.resume(returning: image)
            }
        }
    }
}

#Preview {
    LazyThumbnailView(
        clip: VideoClip(
            assetURL: URL(string: "file://test")!,
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        ),
        clipWidth: 250,
        trackHeight: 52
    )
}
