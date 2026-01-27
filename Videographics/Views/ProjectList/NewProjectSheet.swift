//
//  NewProjectSheet.swift
//  Videographics
//

import SwiftUI

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProjectListViewModel
    let onCreate: (String) -> Void

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $viewModel.newProjectName)
                        .focused($isNameFieldFocused)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(viewModel.newProjectName)
                        dismiss()
                    }
                }
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NewProjectSheet(viewModel: ProjectListViewModel()) { name in
        print("Create project: \(name)")
    }
}
