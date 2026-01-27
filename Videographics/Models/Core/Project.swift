//
//  Project.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date

    @Relationship(deleteRule: .cascade)
    var timeline: Timeline?

    // Thumbnail data for project list
    var thumbnailData: Data?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.timeline = Timeline()
    }

    var duration: CMTime {
        timeline?.duration ?? .zero
    }

    var formattedDuration: String {
        let seconds = duration.seconds
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
