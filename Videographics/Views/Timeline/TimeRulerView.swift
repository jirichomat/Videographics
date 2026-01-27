//
//  TimeRulerView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct TimeRulerView: View {
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat
    let totalDuration: CMTime
    var onSeek: ((CMTime) -> Void)? = nil

    private let trackLabelWidth: CGFloat = 40.0 // Adjusted for tap alignment

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let startSecond = Int(scrollOffset / pixelsPerSecond)
                let endSecond = Int((scrollOffset + size.width) / pixelsPerSecond) + 1
                let maxSecond = Int(totalDuration.seconds) + 10

                for second in startSecond...min(endSecond, maxSecond) {
                    // Add trackLabelWidth offset so ruler aligns with timeline content
                    let x = CGFloat(second) * pixelsPerSecond - scrollOffset + trackLabelWidth

                    // Draw tick marks
                    let tickHeight: CGFloat = second % 5 == 0 ? 10 : 5
                    let tickPath = Path { path in
                        path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(tickPath, with: .color(.secondary), lineWidth: 1)

                    // Draw time labels at 5 second intervals
                    if second % 5 == 0 {
                        let timeString = formatTime(seconds: second)
                        let text = Text(timeString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        context.draw(
                            text,
                            at: CGPoint(x: x, y: size.height - 18),
                            anchor: .bottom
                        )
                    }
                }
            }
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Convert drag position to time (account for track label offset)
                        let adjustedX = value.location.x - trackLabelWidth + scrollOffset
                        let seconds = adjustedX / pixelsPerSecond
                        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
                        onSeek?(time)
                    }
            )
        }
    }

    private func formatTime(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    TimeRulerView(
        pixelsPerSecond: 50,
        scrollOffset: 0,
        totalDuration: CMTime(seconds: 30, preferredTimescale: 600)
    )
    .frame(height: 30)
}
