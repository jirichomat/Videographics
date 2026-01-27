//
//  ProjectListViewModel.swift
//  Videographics
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
class ProjectListViewModel {
    var showingNewProjectSheet = false
    var newProjectName = ""
    var projectToDelete: Project?
    var showingDeleteConfirmation = false

    func createProject(name: String, context: ModelContext) -> Project {
        let project = Project(name: name.isEmpty ? "Untitled Project" : name)
        context.insert(project)
        try? context.save()
        return project
    }

    func deleteProject(_ project: Project, context: ModelContext) {
        // Delete associated media files
        Task {
            try? await FileStorageService.shared.deleteProjectMedia(projectId: project.id)
        }

        context.delete(project)
        try? context.save()
    }

    func confirmDelete(_ project: Project) {
        projectToDelete = project
        showingDeleteConfirmation = true
    }
}
