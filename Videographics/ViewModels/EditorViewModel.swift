//
//  EditorViewModel.swift
//  Videographics
//

import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import CoreMedia
import PhotosUI
import UIKit

enum EditorTool: String, CaseIterable {
    case navigate = "Navigate"
    case select = "Select"
    case move = "Move"
    case blade = "Blade"
    case trim = "Trim"
    case transition = "Transition"
}

@MainActor
@Observable
class EditorViewModel {
    // MARK: - Project
    var project: Project

    // MARK: - Player
    var player: AVPlayer?
    var playerItem: AVPlayerItem?
    var isPlaying = false
    var currentTime: CMTime = .zero

    // MARK: - Timeline
    var pixelsPerSecond: CGFloat = AppConstants.defaultPixelsPerSecond
    var selectedClip: VideoClip?
    var currentTool: EditorTool = .navigate

    // MARK: - Import
    var showingMediaPicker = false
    var showingURLImport = false
    var selectedPhotoItem: PhotosPickerItem?
    var isImporting = false
    var importError: Error?
    var downloadProgress: Double = 0

    // MARK: - Export
    var showingExportSheet = false
    var lastExportedURL: URL?

    // MARK: - Inspector
    var showingInspector = false

    // MARK: - Text Overlays
    var showingTextEditor = false
    var editingTextClip: TextClip?

    // MARK: - Graphics
    var showingGraphicsPicker = false
    var selectedGraphicsItem: PhotosPickerItem?

    // MARK: - Infographics
    var showingInfographicsSheet = false
    var editingInfographicClip: InfographicClip?

    // MARK: - Split Confirmation
    var showingSplitConfirmation = false
    var pendingSplitClip: VideoClip?
    var pendingSplitTime: CMTime = .zero
    var splitFrameBeforeData: Data?
    var splitFrameAfterData: Data?
    var isLoadingSplitFrames = false

    // MARK: - Transition Management
    var showingTransitionSheet = false
    var pendingTransitionFromClip: VideoClip?
    var pendingTransitionToClip: VideoClip?
    var transitionFromFrameData: Data?
    var transitionToFrameData: Data?
    var isLoadingTransitionFrames = false

    // MARK: - Undo/Redo
    let editHistory = EditHistory()

    // MARK: - Time observation
    private var timeObserver: Any?

    init(project: Project) {
        self.project = project
        setupPlayer()
        setupEditHistory()
    }

    private func setupEditHistory() {
        editHistory.onHistoryChanged = { [weak self] in
            guard let self = self else { return }
            self.project.modifiedAt = Date()
            Task {
                await self.rebuildComposition()
            }
        }
    }

    // MARK: - Undo/Redo

    var canUndo: Bool {
        editHistory.canUndo
    }

    var canRedo: Bool {
        editHistory.canRedo
    }

    func undo() {
        pause()
        editHistory.undo()
    }

    func redo() {
        pause()
        editHistory.redo()
    }

    /// Record a move action (called from VideoTrackView after drag ends)
    func recordMoveClip(_ clip: VideoClip, originalStartTime: CMTime, newStartTime: CMTime) {
        let action = MoveClipAction(clip: clip, originalStartTime: originalStartTime, newStartTime: newStartTime)

        if action.hasChange {
            editHistory.record(action)
        } else {
            // No change, but still rebuild composition
            project.modifiedAt = Date()
            Task {
                await rebuildComposition()
            }
        }
    }

    /// Record a trim action (called from VideoTrackView after trim ends)
    func recordTrimClip(_ clip: VideoClip, beforeSnapshot: VideoClipTimingSnapshot, afterSnapshot: VideoClipTimingSnapshot) {
        let action = TrimClipAction(clip: clip, beforeSnapshot: beforeSnapshot, afterSnapshot: afterSnapshot)

        if action.hasChange {
            editHistory.record(action)
        } else {
            // No change, but still rebuild composition
            project.modifiedAt = Date()
            Task {
                await rebuildComposition()
            }
        }
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        player = AVPlayer()
        addTimeObserver()
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: AppConstants.playbackTimescale)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time
            }
        }
    }

    // MARK: - Playback

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: CMTime) {
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    // MARK: - Composition

    func rebuildComposition() async {
        guard let timeline = project.timeline else { return }

        let result = await CompositionEngine.shared.buildComposition(from: timeline)

        if let result = result {
            let newItem = AVPlayerItem(asset: result.composition)

            // Apply video composition for transforms/scaling
            if let videoComposition = result.videoComposition {
                newItem.videoComposition = videoComposition
            }

            await MainActor.run {
                player?.replaceCurrentItem(with: newItem)
                playerItem = newItem
            }
        }
    }

    // MARK: - Import

    func importVideo() async {
        guard let item = selectedPhotoItem else { return }

        isImporting = true
        importError = nil

        do {
            let mediaInfo = try await PhotoLibraryService.shared.processPickerItem(
                item,
                projectId: project.id
            )

            // Create video clip
            let videoClip = VideoClip(
                assetURL: mediaInfo.url,
                timelineStartTime: project.timeline?.duration ?? .zero,
                duration: mediaInfo.duration
            )

            // Generate thumbnails
            let thumbnails = await ThumbnailGenerator.shared.generateThumbnails(
                for: mediaInfo.url,
                duration: mediaInfo.duration
            )
            videoClip.thumbnails = thumbnails

            // Add to main video layer
            if let mainLayer = project.timeline?.mainVideoLayer {
                mainLayer.addClip(videoClip)
            }

            // Update project thumbnail if this is the first clip
            if project.thumbnailData == nil, let firstThumb = thumbnails.first {
                project.thumbnailData = firstThumb
            }

            project.modifiedAt = Date()

            // Rebuild composition
            await rebuildComposition()

            selectedPhotoItem = nil

        } catch {
            importError = error
        }

        isImporting = false
    }

    // MARK: - URL Import

    func importVideoFromURL(_ urlString: String) async {
        isImporting = true
        importError = nil
        downloadProgress = 0

        do {
            let mediaInfo = try await URLVideoDownloader.shared.downloadVideo(
                from: urlString,
                projectId: project.id
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }

            // Create video clip
            let videoClip = VideoClip(
                assetURL: mediaInfo.url,
                timelineStartTime: project.timeline?.duration ?? .zero,
                duration: mediaInfo.duration
            )

            // Generate thumbnails
            let thumbnails = await ThumbnailGenerator.shared.generateThumbnails(
                for: mediaInfo.url,
                duration: mediaInfo.duration
            )
            videoClip.thumbnails = thumbnails

            // Add to main video layer
            if let mainLayer = project.timeline?.mainVideoLayer {
                mainLayer.addClip(videoClip)
            }

            // Update project thumbnail if this is the first clip
            if project.thumbnailData == nil, let firstThumb = thumbnails.first {
                project.thumbnailData = firstThumb
            }

            project.modifiedAt = Date()

            // Rebuild composition
            await rebuildComposition()

            // Dismiss the sheet
            showingURLImport = false

        } catch {
            importError = error
        }

        isImporting = false
        downloadProgress = 0
    }

    // MARK: - Clip Operations

    func selectClip(_ clip: VideoClip?) {
        selectedClip = clip
    }

    func moveClipToLayer(_ clip: VideoClip, from sourceLayer: VideoLayer, to targetLayer: VideoLayer) {
        guard sourceLayer.id != targetLayer.id else { return }

        // Remove from source layer
        sourceLayer.removeClip(clip)

        // Add to target layer
        targetLayer.addClip(clip)

        project.modifiedAt = Date()

        Task {
            await rebuildComposition()
        }
    }

    func getVideoLayerAtOffset(from currentLayer: VideoLayer, yOffset: CGFloat, trackHeight: CGFloat) -> VideoLayer? {
        guard let timeline = project.timeline else { return nil }

        let sortedLayers = timeline.videoLayers.sorted { $0.zIndex > $1.zIndex }
        guard let currentIndex = sortedLayers.firstIndex(where: { $0.id == currentLayer.id }) else { return nil }

        // Calculate how many tracks we've moved (negative = up, positive = down)
        let tracksMoved = Int(round(yOffset / trackHeight))
        let targetIndex = currentIndex + tracksMoved

        // Clamp to valid range
        guard targetIndex >= 0 && targetIndex < sortedLayers.count else { return nil }

        return sortedLayers[targetIndex]
    }

    func deleteSelectedClip() {
        guard let clip = selectedClip,
              let layer = clip.layer else { return }

        // Create delete action and record it
        if let action = DeleteClipAction(clip: clip, layer: layer) {
            editHistory.perform(action)
        } else {
            // Fallback if snapshot fails
            layer.removeClip(clip)
            project.modifiedAt = Date()
            Task {
                await rebuildComposition()
            }
        }

        selectedClip = nil
    }

    func duplicateSelectedClip() {
        guard let clip = selectedClip,
              let layer = clip.layer,
              let assetURL = clip.assetURL else { return }

        // Create new clip starting at the end of the original
        let newClip = VideoClip(
            assetURL: assetURL,
            timelineStartTime: clip.cmTimelineEndTime,
            duration: clip.cmDuration,
            sourceStartTime: clip.cmSourceStartTime,
            scaleMode: clip.scaleMode,
            sourceSize: clip.sourceSize
        )

        // Copy all properties
        newClip.scale = clip.scale
        newClip.positionX = clip.positionX
        newClip.positionY = clip.positionY
        newClip.volume = clip.volume
        newClip.thumbnails = clip.thumbnails

        // Add to the same layer
        layer.addClip(newClip)

        // Select the new clip
        selectedClip = newClip

        project.modifiedAt = Date()

        Task {
            await rebuildComposition()
        }
    }

    func setScaleMode(_ mode: VideoScaleMode) {
        guard let clip = selectedClip else { return }

        // Capture before state
        let beforeSnapshot = VideoClipTransformSnapshot(from: clip)

        // Apply change
        clip.scaleMode = mode

        // Capture after state and record action
        let afterSnapshot = VideoClipTransformSnapshot(from: clip)
        let action = TransformClipAction(clip: clip, beforeSnapshot: beforeSnapshot, afterSnapshot: afterSnapshot)

        if action.hasChange {
            editHistory.record(action)
        } else {
            // No change, still update modified date
            project.modifiedAt = Date()
            Task {
                await rebuildComposition()
            }
        }
    }

    func cycleScaleMode() {
        guard let clip = selectedClip else { return }

        // Capture before state
        let beforeSnapshot = VideoClipTransformSnapshot(from: clip)

        let modes = VideoScaleMode.allCases
        if let currentIndex = modes.firstIndex(of: clip.scaleMode) {
            let nextIndex = (currentIndex + 1) % modes.count
            clip.scaleMode = modes[nextIndex]

            // Capture after state and record action
            let afterSnapshot = VideoClipTransformSnapshot(from: clip)
            let action = TransformClipAction(clip: clip, beforeSnapshot: beforeSnapshot, afterSnapshot: afterSnapshot)

            if action.hasChange {
                editHistory.record(action)
            } else {
                project.modifiedAt = Date()
                Task {
                    await rebuildComposition()
                }
            }
        }
    }

    func splitClipAtPlayhead() {
        guard currentTool == .blade else { return }

        // Find clip at current playhead position
        guard let timeline = project.timeline else { return }

        for layer in timeline.videoLayers {
            for clip in layer.clips {
                if CMTimeCompare(currentTime, clip.cmTimelineStartTime) >= 0 &&
                   CMTimeCompare(currentTime, clip.cmTimelineEndTime) < 0 {
                    // Split this clip
                    splitClip(clip, at: currentTime)
                    return
                }
            }
        }
    }

    /// Split a specific clip at the given time (for blade tool tap-to-split)
    /// Shows confirmation dialog instead of immediately splitting
    func splitClipAtTime(_ clip: VideoClip, at time: CMTime) {
        guard currentTool == .blade else { return }

        // Ensure the time is within the clip's range
        guard CMTimeCompare(time, clip.cmTimelineStartTime) > 0 &&
              CMTimeCompare(time, clip.cmTimelineEndTime) < 0 else {
            return
        }

        // Store pending split and show confirmation
        pendingSplitClip = clip
        pendingSplitTime = time
        showingSplitConfirmation = true

        // Load frame thumbnails at split point
        Task {
            await loadSplitFrameThumbnails()
        }
    }

    /// Load frame thumbnails at the split point
    private func loadSplitFrameThumbnails() async {
        guard let clip = pendingSplitClip,
              let assetURL = clip.assetURL else {
            print("Split frames: No clip or asset URL available")
            return
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            print("Split frames: File not found at \(assetURL.path)")
            isLoadingSplitFrames = false
            return
        }

        isLoadingSplitFrames = true
        splitFrameBeforeData = nil
        splitFrameAfterData = nil

        // Calculate source times for the frames
        let splitOffsetInClip = CMTimeSubtract(pendingSplitTime, clip.cmTimelineStartTime)
        let sourceTimeAtSplit = CMTimeAdd(clip.cmSourceStartTime, splitOffsetInClip)

        // Frame duration (assuming 30fps, adjust as needed)
        let frameDuration = CMTime(value: 1, timescale: 30)

        // Time for last frame of part 1 (one frame before split)
        var beforeTime = CMTimeSubtract(sourceTimeAtSplit, frameDuration)
        // Ensure beforeTime is not negative
        if CMTimeCompare(beforeTime, .zero) < 0 {
            beforeTime = .zero
        }

        // Time for first frame of part 2 (at split point)
        let afterTime = sourceTimeAtSplit

        // Generate thumbnails in parallel
        async let beforeThumb = ThumbnailGenerator.shared.generateThumbnail(for: assetURL, at: beforeTime)
        async let afterThumb = ThumbnailGenerator.shared.generateThumbnail(for: assetURL, at: afterTime)

        splitFrameBeforeData = await beforeThumb
        splitFrameAfterData = await afterThumb

        isLoadingSplitFrames = false
    }

    /// Fine-tune split time by stepping frames
    func adjustSplitTime(frames: Int) {
        guard let clip = pendingSplitClip else { return }

        // Frame duration at 30fps
        let frameDuration = CMTime(value: 1, timescale: 30)
        let adjustment = CMTimeMultiply(frameDuration, multiplier: Int32(frames))
        let newTime = CMTimeAdd(pendingSplitTime, adjustment)

        // Ensure the new time is still within the clip's range (with at least 1 frame margin)
        let minTime = CMTimeAdd(clip.cmTimelineStartTime, frameDuration)
        let maxTime = CMTimeSubtract(clip.cmTimelineEndTime, frameDuration)

        guard CMTimeCompare(newTime, minTime) >= 0 &&
              CMTimeCompare(newTime, maxTime) <= 0 else {
            return
        }

        pendingSplitTime = newTime

        // Reload frame thumbnails
        Task {
            await loadSplitFrameThumbnails()
        }
    }

    /// Fine-tune split time by milliseconds
    func adjustSplitTimeMs(milliseconds: Int) {
        guard let clip = pendingSplitClip else { return }

        let adjustment = CMTime(value: CMTimeValue(milliseconds), timescale: 1000)
        let newTime = CMTimeAdd(pendingSplitTime, adjustment)

        // Ensure the new time is still within the clip's range
        let frameDuration = CMTime(value: 1, timescale: 30)
        let minTime = CMTimeAdd(clip.cmTimelineStartTime, frameDuration)
        let maxTime = CMTimeSubtract(clip.cmTimelineEndTime, frameDuration)

        guard CMTimeCompare(newTime, minTime) >= 0 &&
              CMTimeCompare(newTime, maxTime) <= 0 else {
            return
        }

        pendingSplitTime = newTime

        // Reload frame thumbnails
        Task {
            await loadSplitFrameThumbnails()
        }
    }

    /// Confirm and execute the pending split
    func confirmSplit() {
        guard let clip = pendingSplitClip else { return }
        splitClip(clip, at: pendingSplitTime)
        cancelSplit()
    }

    /// Cancel the pending split
    func cancelSplit() {
        pendingSplitClip = nil
        pendingSplitTime = .zero
        showingSplitConfirmation = false
        splitFrameBeforeData = nil
        splitFrameAfterData = nil
        isLoadingSplitFrames = false
    }

    /// Get preview info for the pending split
    var pendingSplitInfo: (firstDuration: CMTime, secondDuration: CMTime, splitOffsetInClip: CMTime)? {
        guard let clip = pendingSplitClip else { return nil }

        let splitOffset = CMTimeSubtract(pendingSplitTime, clip.cmTimelineStartTime)
        let firstDuration = splitOffset
        let secondDuration = CMTimeSubtract(clip.cmDuration, splitOffset)

        return (firstDuration, secondDuration, splitOffset)
    }

    private func splitClip(_ clip: VideoClip, at time: CMTime) {
        guard let layer = clip.layer,
              let assetURL = clip.assetURL else { return }

        // Capture original duration for undo
        let originalDuration = clip.cmDuration

        // Calculate the split point relative to the clip's timeline start
        let splitOffset = CMTimeSubtract(time, clip.cmTimelineStartTime)

        // First part: original clip trimmed to end at split point
        let firstDuration = splitOffset

        // Second part: new clip starting at split point
        let secondDuration = CMTimeSubtract(clip.cmDuration, splitOffset)
        let secondSourceStart = CMTimeAdd(clip.cmSourceStartTime, splitOffset)

        // Update first clip
        clip.setDuration(firstDuration)

        // Create second clip
        let secondClip = VideoClip(
            assetURL: assetURL,
            timelineStartTime: time,
            duration: secondDuration,
            sourceStartTime: secondSourceStart,
            scaleMode: clip.scaleMode,
            sourceSize: clip.sourceSize
        )

        // Copy scale/transform properties
        secondClip.scale = clip.scale
        secondClip.positionX = clip.positionX
        secondClip.positionY = clip.positionY
        secondClip.volume = clip.volume

        // Copy thumbnails (simplified - would need proper thumbnail slicing)
        secondClip.thumbnails = clip.thumbnails

        layer.addClip(secondClip)

        // Record split action for undo/redo
        let action = SplitClipAction(
            originalClip: clip,
            secondClip: secondClip,
            layer: layer,
            originalDuration: originalDuration
        )
        editHistory.record(action)
    }

    // MARK: - Transition Management

    /// Open transition sheet for adding/editing transition between two clips
    func openTransitionSheet(fromClip: VideoClip, toClip: VideoClip) {
        pendingTransitionFromClip = fromClip
        pendingTransitionToClip = toClip
        showingTransitionSheet = true

        // Load frame thumbnails
        Task {
            await loadTransitionFrameThumbnails()
        }
    }

    /// Load frame thumbnails for transition preview
    private func loadTransitionFrameThumbnails() async {
        guard let fromClip = pendingTransitionFromClip,
              let toClip = pendingTransitionToClip,
              let fromURL = fromClip.assetURL,
              let toURL = toClip.assetURL else {
            return
        }

        isLoadingTransitionFrames = true
        transitionFromFrameData = nil
        transitionToFrameData = nil

        // Get last frame of fromClip and first frame of toClip
        let fromTime = CMTimeSubtract(
            CMTimeAdd(fromClip.cmSourceStartTime, fromClip.cmDuration),
            CMTime(value: 1, timescale: 30) // One frame before end
        )
        let toTime = toClip.cmSourceStartTime

        async let fromThumb = ThumbnailGenerator.shared.generateThumbnail(for: fromURL, at: fromTime)
        async let toThumb = ThumbnailGenerator.shared.generateThumbnail(for: toURL, at: toTime)

        transitionFromFrameData = await fromThumb
        transitionToFrameData = await toThumb

        isLoadingTransitionFrames = false
    }

    /// Confirm and add the transition
    func confirmTransition(type: TransitionType, duration: Double) {
        guard let fromClip = pendingTransitionFromClip else { return }

        // Create new transition or update existing
        let transition = Transition(
            type: type,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        transition.fromClipId = fromClip.id
        transition.toClipId = pendingTransitionToClip?.id

        fromClip.outTransition = transition
        project.modifiedAt = Date()

        cancelTransition()

        Task {
            await rebuildComposition()
        }
    }

    /// Remove transition from the pending clip
    func removeTransition() {
        guard let fromClip = pendingTransitionFromClip else { return }

        fromClip.outTransition = nil
        project.modifiedAt = Date()

        cancelTransition()

        Task {
            await rebuildComposition()
        }
    }

    /// Cancel the transition sheet
    func cancelTransition() {
        pendingTransitionFromClip = nil
        pendingTransitionToClip = nil
        transitionFromFrameData = nil
        transitionToFrameData = nil
        isLoadingTransitionFrames = false
        showingTransitionSheet = false
    }

    /// Find adjacent clips in the same layer (for transition tool tap)
    func findAdjacentClips(at time: CMTime) -> (from: VideoClip, to: VideoClip)? {
        guard let timeline = project.timeline else { return nil }

        for layer in timeline.videoLayers {
            let sortedClips = layer.sortedClips

            for i in 0..<(sortedClips.count - 1) {
                let fromClip = sortedClips[i]
                let toClip = sortedClips[i + 1]

                // Check if the tap is near the junction between these clips
                let gapStart = fromClip.cmTimelineEndTime
                let gapEnd = toClip.cmTimelineStartTime

                // Check if time is within or near the gap (or junction if no gap)
                let checkStart = CMTimeSubtract(gapStart, CMTime(seconds: 0.5, preferredTimescale: 600))
                let checkEnd = CMTimeAdd(gapEnd, CMTime(seconds: 0.5, preferredTimescale: 600))

                if CMTimeCompare(time, checkStart) >= 0 && CMTimeCompare(time, checkEnd) <= 0 {
                    return (fromClip, toClip)
                }
            }
        }

        return nil
    }

    /// Handle tap on timeline when transition tool is active
    func handleTransitionToolTap(at time: CMTime) {
        guard currentTool == .transition else { return }

        if let (fromClip, toClip) = findAdjacentClips(at: time) {
            openTransitionSheet(fromClip: fromClip, toClip: toClip)
        }
    }

    /// Handle tap on a specific clip junction for transition
    func handleTransitionBetweenClips(_ fromClip: VideoClip, _ toClip: VideoClip) {
        openTransitionSheet(fromClip: fromClip, toClip: toClip)
    }

    // MARK: - Zoom

    func zoomIn() {
        pixelsPerSecond = min(pixelsPerSecond * 1.5, AppConstants.maxPixelsPerSecond)
    }

    func zoomOut() {
        pixelsPerSecond = max(pixelsPerSecond / 1.5, AppConstants.minPixelsPerSecond)
    }

    func resetUI() {
        pause()
        currentTool = .navigate
        selectedClip = nil
        pixelsPerSecond = AppConstants.defaultPixelsPerSecond
        seek(to: .zero)
        showingInspector = false
        showingTextEditor = false
        showingInfographicsSheet = false
        editingTextClip = nil
        editingInfographicClip = nil
    }

    // MARK: - Formatting

    var formattedCurrentTime: String {
        let seconds = currentTime.seconds
        guard seconds.isFinite else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", minutes, secs, frames)
    }

    // MARK: - Text Overlay Operations

    func addTextOverlay() {
        editingTextClip = nil
        showingTextEditor = true
    }

    func editTextClip(_ clip: TextClip) {
        editingTextClip = clip
        showingTextEditor = true
    }

    func saveTextClip(
        text: String,
        fontName: String,
        fontSize: Float,
        textColorHex: String,
        alignment: TextClipAlignment,
        positionX: Float,
        positionY: Float
    ) {
        if let existingClip = editingTextClip {
            // Update existing clip
            existingClip.text = text
            existingClip.fontName = fontName
            existingClip.fontSize = fontSize
            existingClip.textColorHex = textColorHex
            existingClip.alignment = alignment
            existingClip.positionX = positionX
            existingClip.positionY = positionY
        } else {
            // Create new text clip
            let textClip = TextClip(
                text: text,
                timelineStartTime: currentTime,
                duration: CMTime(seconds: 5.0, preferredTimescale: 600),
                fontName: fontName,
                fontSize: fontSize,
                textColor: textColorHex,
                alignment: alignment,
                positionX: positionX,
                positionY: positionY
            )

            // Add to main text layer
            if let textLayer = project.timeline?.mainTextLayer {
                textLayer.addClip(textClip)
            }
        }

        project.modifiedAt = Date()
        editingTextClip = nil
        showingTextEditor = false

        Task {
            await rebuildComposition()
        }
    }

    func deleteTextClip(_ clip: TextClip) {
        guard let layer = clip.layer else { return }
        layer.removeClip(clip)
        project.modifiedAt = Date()

        Task {
            await rebuildComposition()
        }
    }

    // MARK: - Graphics Operations

    func addGraphicsOverlay() {
        showingGraphicsPicker = true
    }

    func importGraphics() async {
        guard let item = selectedGraphicsItem else { return }

        do {
            // Load image data
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }

            guard let image = UIImage(data: data) else {
                return
            }

            // Create graphics clip
            let graphicsClip = GraphicsClip(
                imageData: data,
                timelineStartTime: currentTime,
                duration: CMTime(seconds: 5.0, preferredTimescale: 600),
                sourceSize: image.size
            )

            // Add to main graphics layer
            if let graphicsLayer = project.timeline?.mainGraphicsLayer {
                graphicsLayer.addClip(graphicsClip)
            }

            project.modifiedAt = Date()
            selectedGraphicsItem = nil
            showingGraphicsPicker = false

            await rebuildComposition()

        } catch {
            print("Failed to import graphics: \(error)")
        }
    }

    func deleteGraphicsClip(_ clip: GraphicsClip) {
        guard let layer = clip.layer else { return }
        layer.removeClip(clip)
        project.modifiedAt = Date()

        Task {
            await rebuildComposition()
        }
    }

    // MARK: - Infographics Operations

    func addInfographic() {
        editingInfographicClip = nil
        showingInfographicsSheet = true
    }

    func editInfographicClip(_ clip: InfographicClip) {
        editingInfographicClip = clip
        showingInfographicsSheet = true
    }

    func saveInfographicClip(
        chartType: InfographicChartType,
        stylePreset: InfographicStylePreset,
        chartData: ChartData,
        positionX: Float,
        positionY: Float,
        scale: Float
    ) {
        if let existingClip = editingInfographicClip {
            // Update existing clip
            existingClip.chartType = chartType
            existingClip.stylePreset = stylePreset
            existingClip.chartData = chartData
            existingClip.positionX = positionX
            existingClip.positionY = positionY
            existingClip.scale = scale
        } else {
            // Create new infographic clip
            let infographicClip = InfographicClip(
                chartType: chartType,
                stylePreset: stylePreset,
                chartData: chartData,
                timelineStartTime: currentTime,
                duration: CMTime(seconds: 5.0, preferredTimescale: 600),
                positionX: positionX,
                positionY: positionY,
                scale: scale
            )

            // Add to main infographic layer
            if let infographicLayer = project.timeline?.mainInfographicLayer {
                infographicLayer.addClip(infographicClip)
            }
        }

        project.modifiedAt = Date()
        editingInfographicClip = nil
        showingInfographicsSheet = false

        Task {
            await rebuildComposition()
        }
    }

    func deleteInfographicClip(_ clip: InfographicClip) {
        guard let layer = clip.layer else { return }
        layer.removeClip(clip)
        project.modifiedAt = Date()

        Task {
            await rebuildComposition()
        }
    }
}
