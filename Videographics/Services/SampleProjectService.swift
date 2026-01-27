//
//  SampleProjectService.swift
//  Videographics
//

import Foundation
import SwiftData
import AVFoundation
import CoreMedia
import UIKit
import Combine

@MainActor
class SampleProjectService: ObservableObject {
    @Published var isSettingUp = false
    @Published var setupProgress: Double = 0
    @Published var statusMessage = "Preparing..."
    @Published var setupComplete = false
    @Published var setupError: Error?
    @Published var createdProject: Project?

    private let hasLaunchedKey = "hasLaunchedBefore"

    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasLaunchedKey)
    }

    func markAsLaunched() {
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
    }

    /// Setup sample project if this is the first launch
    func setupSampleProjectIfNeeded(modelContext: ModelContext) async {
        // Check if there are already projects
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        let existingProjects = (try? modelContext.fetch(descriptor)) ?? []

        guard existingProjects.isEmpty && isFirstLaunch else {
            // Use most recent existing project
            createdProject = existingProjects.first
            setupComplete = true
            return
        }

        isSettingUp = true
        statusMessage = "Creating sample project..."

        do {
            // Create the project first
            let project = Project(name: "Sample Project")
            modelContext.insert(project)
            try modelContext.save()

            statusMessage = "Downloading sample video..."

            // Download sample video (using the short "For Bigger Blazes" video - 15 seconds)
            let sampleURL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"

            let mediaInfo = try await URLVideoDownloader.shared.downloadVideo(
                from: sampleURL,
                projectId: project.id
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.setupProgress = progress * 0.8 // Reserve 20% for final setup
                }
            }

            statusMessage = "Setting up timeline..."
            setupProgress = 0.9

            // Create video clip and add to timeline
            guard let timeline = project.timeline,
                  let mainVideoLayer = timeline.mainVideoLayer else {
                throw SampleProjectError.timelineNotFound
            }

            let videoClip = VideoClip(
                assetURL: mediaInfo.url,
                timelineStartTime: .zero,
                duration: mediaInfo.duration,
                sourceStartTime: .zero,
                scaleMode: .fill,
                sourceSize: mediaInfo.naturalSize
            )

            mainVideoLayer.addClip(videoClip)

            // Generate thumbnail for project
            await generateProjectThumbnail(for: project, from: mediaInfo.url)

            try modelContext.save()

            setupProgress = 1.0
            statusMessage = "Ready!"
            markAsLaunched()
            createdProject = project

            // Small delay to show completion
            try? await Task.sleep(for: .milliseconds(500))

            setupComplete = true
            isSettingUp = false

        } catch {
            setupError = error
            isSettingUp = false
            setupComplete = true // Allow proceeding even on error
            markAsLaunched() // Don't retry on every launch if it fails
        }
    }

    private func generateProjectThumbnail(for project: Project, from videoURL: URL) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)

        do {
            let cgImage = try await generator.image(at: .zero).image
            let uiImage = UIImage(cgImage: cgImage)
            project.thumbnailData = uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            // Thumbnail generation failed, not critical
            print("Failed to generate thumbnail: \(error)")
        }
    }
}

enum SampleProjectError: LocalizedError {
    case timelineNotFound
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .timelineNotFound:
            return "Failed to setup project timeline"
        case .downloadFailed:
            return "Failed to download sample video"
        }
    }
}
