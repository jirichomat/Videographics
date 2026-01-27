//
//  ProjectListView.swift
//  Videographics
//

import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.modifiedAt, order: .reverse) private var projects: [Project]

    @State private var viewModel = ProjectListViewModel()
    @State private var selectedProject: Project?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyStateView
                } else {
                    projectsGrid
                }
            }
            .navigationTitle("Videographics")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.newProjectName = ""
                        viewModel.showingNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingNewProjectSheet) {
                NewProjectSheet(viewModel: viewModel) { name in
                    let project = viewModel.createProject(name: name, context: modelContext)
                    selectedProject = project
                }
            }
            .alert("Delete Project?", isPresented: $viewModel.showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let project = viewModel.projectToDelete {
                        viewModel.deleteProject(project, context: modelContext)
                    }
                }
            } message: {
                Text("This will permanently delete the project and all its media. This action cannot be undone.")
            }
            .navigationDestination(item: $selectedProject) { project in
                EditorView(project: project)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "film")
        } description: {
            Text("Create your first video project to get started.")
        } actions: {
            Button("New Project") {
                viewModel.newProjectName = ""
                viewModel.showingNewProjectSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var projectsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(projects) { project in
                    ProjectCardView(project: project)
                        .onTapGesture {
                            selectedProject = project
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.confirmDelete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }
}

#Preview {
    ProjectListView()
        .modelContainer(for: Project.self, inMemory: true)
}
