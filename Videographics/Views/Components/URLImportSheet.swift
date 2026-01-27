//
//  URLImportSheet.swift
//  Videographics
//

import SwiftUI

struct URLImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isImporting: Bool
    let onImport: (String) -> Void

    @State private var customURL: String = ""
    @State private var downloadProgress: Double = 0

    var body: some View {
        NavigationStack {
            List {
                // Custom URL Section
                Section("Custom URL") {
                    TextField("Enter video URL", text: $customURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    if !customURL.isEmpty {
                        Button {
                            startImport(url: customURL)
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .disabled(isImporting)
                    }
                }

                // Sample Videos Section
                Section("Sample Videos") {
                    ForEach(SampleVideos.videos, id: \.url) { video in
                        Button {
                            startImport(url: video.url)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(video.name)
                                        .foregroundStyle(.primary)
                                    Text(video.url)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .disabled(isImporting)
                    }
                }

                // Progress Section
                if isImporting {
                    Section("Downloading...") {
                        VStack(spacing: 8) {
                            ProgressView(value: downloadProgress)
                            Text("\(Int(downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
            }
        }
    }

    private func startImport(url: String) {
        onImport(url)
    }
}

#Preview {
    URLImportSheet(isImporting: .constant(false)) { url in
        print("Import: \(url)")
    }
}
