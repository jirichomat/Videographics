//
//  ProjectCardView.swift
//  Videographics
//

import SwiftUI

struct ProjectCardView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail area
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))

                if let thumbnailData = project.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Project info
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(project.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ProjectCardView(project: Project(name: "Test Project"))
        .frame(width: 150)
        .padding()
}
