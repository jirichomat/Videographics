//
//  TimelineViewModel.swift
//  Videographics
//

import Foundation
import SwiftUI
import CoreMedia

@MainActor
@Observable
class TimelineViewModel {
    var scrollOffset: CGFloat = 0
    var isDraggingPlayhead = false

    // Convert time to x position
    func xPosition(for time: CMTime, pixelsPerSecond: CGFloat) -> CGFloat {
        return CGFloat(time.seconds) * pixelsPerSecond
    }

    // Convert x position to time
    func time(for xPosition: CGFloat, pixelsPerSecond: CGFloat) -> CMTime {
        let seconds = xPosition / pixelsPerSecond
        return CMTime(seconds: Double(seconds), preferredTimescale: AppConstants.playbackTimescale)
    }

    // Calculate clip width
    func clipWidth(for clip: VideoClip, pixelsPerSecond: CGFloat) -> CGFloat {
        return CGFloat(clip.cmDuration.seconds) * pixelsPerSecond
    }

    // Calculate total timeline width
    func timelineWidth(for duration: CMTime, pixelsPerSecond: CGFloat, minWidth: CGFloat) -> CGFloat {
        let contentWidth = CGFloat(duration.seconds) * pixelsPerSecond
        return max(contentWidth + 200, minWidth) // Add padding for dropping clips at the end
    }
}
