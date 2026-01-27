//
//  VideographicsApp.swift
//  Videographics
//
//  Created by Jiri Chomat on 27.01.2026.
//

import SwiftUI
import SwiftData

@main
struct VideographicsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Timeline.self,
            VideoLayer.self,
            AudioLayer.self,
            VideoClip.self,
            AudioClip.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Root View

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sampleProjectService = SampleProjectService()

    var body: some View {
        Group {
            if sampleProjectService.setupComplete {
                if let project = sampleProjectService.createdProject {
                    // Go directly to editor with the project
                    NavigationStack {
                        EditorView(project: project)
                    }
                } else {
                    // Fallback to project list if no project
                    ProjectListView()
                }
            } else {
                FirstLaunchView(sampleProjectService: sampleProjectService)
            }
        }
        .task {
            await sampleProjectService.setupSampleProjectIfNeeded(modelContext: modelContext)
        }
    }
}
