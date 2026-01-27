//
//  EditorView.swift
//  Videographics
//

import SwiftUI
import PhotosUI

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project
    @State private var viewModel: EditorViewModel

    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: EditorViewModel(project: project))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Video Preview
                VideoPreviewView(viewModel: viewModel)
                    .frame(height: geometry.size.height * 0.45)

                // Toolbar
                ToolbarView(viewModel: viewModel)

                Divider()

                // Timeline
                TimelineContainerView(viewModel: viewModel)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.pause()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Projects")
                    }
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Undo button
                Button {
                    viewModel.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)

                // Redo button
                Button {
                    viewModel.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)

                // Export button
                Button {
                    viewModel.pause()
                    viewModel.showingExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(project.timeline?.isEmpty ?? true)
            }
        }
        .photosPicker(
            isPresented: $viewModel.showingMediaPicker,
            selection: $viewModel.selectedPhotoItem,
            matching: .videos,
            photoLibrary: .shared()
        )
        .onChange(of: viewModel.selectedPhotoItem) { _, newValue in
            if newValue != nil {
                Task {
                    await viewModel.importVideo()
                }
            }
        }
        .sheet(isPresented: $viewModel.showingURLImport) {
            URLImportSheet(
                isImporting: $viewModel.isImporting
            ) { urlString in
                Task {
                    await viewModel.importVideoFromURL(urlString)
                }
            }
            .interactiveDismissDisabled(viewModel.isImporting)
        }
        .sheet(isPresented: $viewModel.showingExportSheet) {
            if let timeline = project.timeline {
                ExportSheet(
                    timeline: timeline,
                    projectId: project.id,
                    onExportComplete: { url in
                        viewModel.lastExportedURL = url
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showingSplitConfirmation) {
            SplitConfirmationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingTransitionSheet) {
            TransitionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingInspector) {
            InspectorView(viewModel: viewModel)
        }
        .task {
            await viewModel.rebuildComposition()
        }
        .alert("Import Failed", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button("OK") {
                viewModel.importError = nil
            }
        } message: {
            if let error = viewModel.importError {
                Text(error.localizedDescription)
            }
        }
    }
}

#Preview {
    NavigationStack {
        EditorView(project: Project(name: "Test Project"))
    }
}
