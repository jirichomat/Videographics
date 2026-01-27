//
//  PlayheadView.swift
//  Videographics
//

import SwiftUI
import CoreMedia

struct PlayheadView: View {
    let currentTime: CMTime
    let pixelsPerSecond: CGFloat
    let height: CGFloat

    private var xPosition: CGFloat {
        CGFloat(currentTime.seconds) * pixelsPerSecond + AppConstants.trackLabelWidth
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Playhead line
            Rectangle()
                .fill(Color.red)
                .frame(width: AppConstants.playheadWidth, height: height)

            // Playhead handle
            PlayheadHandle()
                .offset(y: -8)
        }
        .offset(x: xPosition - AppConstants.playheadWidth / 2)
    }
}

struct PlayheadHandle: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.addLine(to: CGPoint(x: 12, y: 8))
            path.addLine(to: CGPoint(x: 6, y: 16))
            path.addLine(to: CGPoint(x: 0, y: 8))
            path.closeSubpath()
        }
        .fill(Color.red)
        .frame(width: 12, height: 16)
        .offset(x: -5)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)

        PlayheadView(
            currentTime: CMTime(seconds: 2, preferredTimescale: 600),
            pixelsPerSecond: 50,
            height: 100
        )
    }
    .frame(height: 120)
}
