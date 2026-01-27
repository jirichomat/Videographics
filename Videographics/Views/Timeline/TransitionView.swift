//
//  TransitionView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

/// Visual indicator for a transition between two clips on the timeline
struct TransitionView: View {
    let transition: Transition
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    var isSelected: Bool = false
    var isTransitionToolActive: Bool = false

    private var transitionWidth: CGFloat {
        CGFloat(transition.cmDuration.seconds) * pixelsPerSecond
    }

    var body: some View {
        ZStack {
            // Background
            transitionBackground

            // Icon and label
            VStack(spacing: 2) {
                Image(systemName: transition.type.icon)
                    .font(.system(size: min(transitionWidth * 0.3, 14)))
                    .foregroundStyle(.white)

                if transitionWidth > 40 {
                    Text(String(format: "%.1fs", transition.durationSeconds))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Selection border
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.yellow, lineWidth: 2)
            }

            // Tap hint when transition tool is active
            if isTransitionToolActive && !isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.purple.opacity(0.5), lineWidth: 1)
            }
        }
        .frame(width: max(transitionWidth, 20), height: trackHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transitionBackground: some View {
        // Gradient background that represents the transition
        ZStack {
            // Base shape
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.6),
                            Color.purple.opacity(0.9),
                            Color.purple.opacity(0.6)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // Diagonal pattern to indicate transition
            Canvas { context, size in
                let stripeWidth: CGFloat = 6
                let numberOfStripes = Int(size.width / stripeWidth) + 2

                for i in 0..<numberOfStripes {
                    let x = CGFloat(i) * stripeWidth
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x - size.height * 0.5, y: size.height))

                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.15)),
                        lineWidth: 1
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

/// Placeholder view shown between clips where a transition can be added
struct TransitionPlaceholderView: View {
    let trackHeight: CGFloat
    var isHighlighted: Bool = false

    var body: some View {
        ZStack {
            // Dashed border rectangle
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: [4, 4]
                    )
                )
                .foregroundStyle(isHighlighted ? Color.purple : Color.gray.opacity(0.5))

            // Plus icon
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHighlighted ? Color.purple : Color.gray.opacity(0.5))
        }
        .frame(width: 24, height: trackHeight * 0.6)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 20) {
        // Normal transition
        TransitionView(
            transition: Transition(type: .crossDissolve, duration: CMTime(seconds: 0.5, preferredTimescale: 600)),
            pixelsPerSecond: 50,
            trackHeight: 52
        )

        // Selected transition
        TransitionView(
            transition: Transition(type: .fadeToBlack, duration: CMTime(seconds: 0.75, preferredTimescale: 600)),
            pixelsPerSecond: 50,
            trackHeight: 52,
            isSelected: true
        )

        // Longer transition
        TransitionView(
            transition: Transition(type: .slideLeft, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
            pixelsPerSecond: 50,
            trackHeight: 52
        )

        // Placeholder
        TransitionPlaceholderView(trackHeight: 52)

        // Highlighted placeholder
        TransitionPlaceholderView(trackHeight: 52, isHighlighted: true)
    }
    .padding()
    .background(Color(.systemBackground))
}
