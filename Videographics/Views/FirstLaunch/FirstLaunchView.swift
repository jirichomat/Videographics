//
//  FirstLaunchView.swift
//  Videographics
//

import SwiftUI

struct FirstLaunchView: View {
    @ObservedObject var sampleProjectService: SampleProjectService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/logo area
            Image(systemName: "film.stack")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("Videographics")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 16) {
                Text(sampleProjectService.statusMessage)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ProgressView(value: sampleProjectService.setupProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text("\(Int(sampleProjectService.setupProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if let error = sampleProjectService.setupError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text("Setup encountered an issue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            Text("Setting up your first project with a sample video...")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    @Previewable @StateObject var service = SampleProjectService()
    FirstLaunchView(sampleProjectService: service)
}
