//
//  ToolbarView.swift
//  Videographics
//

import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Add Media Menu
            Menu {
                Button {
                    viewModel.showingMediaPicker = true
                } label: {
                    Label("From Photo Library", systemImage: "photo.on.rectangle")
                }

                Button {
                    viewModel.showingURLImport = true
                } label: {
                    Label("From URL", systemImage: "link")
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 18))
                    Text("Add")
                        .font(.caption2)
                }
                .frame(width: 50, height: 44)
                .foregroundStyle(.primary)
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 8)

            // Editing tools
            ToolbarButton(
                icon: "hand.draw",
                label: "Navigate",
                isSelected: viewModel.currentTool == .navigate
            ) {
                viewModel.currentTool = .navigate
            }

            ToolbarButton(
                icon: "cursorarrow",
                label: "Select",
                isSelected: viewModel.currentTool == .select
            ) {
                viewModel.currentTool = .select
            }

            ToolbarButton(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                label: "Move",
                isSelected: viewModel.currentTool == .move
            ) {
                viewModel.currentTool = .move
            }

            ToolbarButton(
                icon: "scissors",
                label: "Blade",
                isSelected: viewModel.currentTool == .blade
            ) {
                viewModel.currentTool = .blade
            }

            ToolbarButton(
                icon: "timeline.selection",
                label: "Trim",
                isSelected: viewModel.currentTool == .trim
            ) {
                viewModel.currentTool = .trim
            }

            ToolbarButton(
                icon: "rectangle.on.rectangle.angled",
                label: "Transition",
                isSelected: viewModel.currentTool == .transition
            ) {
                viewModel.currentTool = .transition
            }

            Spacer()

            // Scale mode (when clip selected)
            if let clip = viewModel.selectedClip {
                Menu {
                    ForEach(VideoScaleMode.allCases, id: \.self) { mode in
                        Button {
                            viewModel.setScaleMode(mode)
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                if clip.scaleMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: scaleModeIcon(for: clip.scaleMode))
                            .font(.system(size: 16))
                        Text(clip.scaleMode.displayName)
                            .font(.caption2)
                    }
                    .frame(width: 50, height: 44)
                    .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 4)
            }

            // Zoom controls
            HStack(spacing: 4) {
                Button {
                    viewModel.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Clip actions (when clip selected)
            if viewModel.selectedClip != nil {
                // Inspector button
                Button {
                    viewModel.showingInspector = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)

                // Delete button
                Button(role: .destructive) {
                    viewModel.deleteSelectedClip()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color(.systemBackground))
    }

    private func scaleModeIcon(for mode: VideoScaleMode) -> String {
        switch mode {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fill: return "arrow.up.left.and.arrow.down.right"
        case .stretch: return "arrow.left.and.right"
        }
    }
}

struct ToolbarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 50, height: 44)
            .foregroundStyle(isSelected ? .blue : .primary)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ToolbarView(viewModel: EditorViewModel(project: Project(name: "Test")))
}
