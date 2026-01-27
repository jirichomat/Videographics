//
//  InfographicsSheet.swift
//  Videographics
//

import SwiftUI

struct InfographicsSheet: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var chartType: InfographicChartType = .bar
    @State private var stylePreset: InfographicStylePreset = .tikTokNeon
    @State private var jsonText: String = ""
    @State private var chartData: ChartData?
    @State private var parseError: String?
    @State private var positionX: Float = 0
    @State private var positionY: Float = 0
    @State private var scale: Float = 0.8
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Chart Type Selection
                    chartTypeSection

                    // Style Preset Selection
                    stylePresetSection

                    // JSON Data Input
                    dataInputSection

                    // Position & Scale
                    transformSection

                    // Preview
                    previewSection
                }
                .padding()
            }
            .navigationTitle(viewModel.editingInfographicClip == nil ? "Add Infographic" : "Edit Infographic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveInfographic()
                    }
                    .disabled(chartData == nil)
                }
            }
            .onAppear {
                loadExistingClip()
            }
            .onChange(of: chartType) { _, _ in
                if chartData == nil {
                    loadSampleData()
                }
                updatePreview()
            }
            .onChange(of: stylePreset) { _, _ in
                updatePreview()
            }
            .onChange(of: jsonText) { _, _ in
                parseJSON()
            }
        }
    }

    // MARK: - Chart Type Section

    private var chartTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chart Type")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(InfographicChartType.allCases, id: \.rawValue) { type in
                        ChartTypeButton(
                            type: type,
                            isSelected: chartType == type
                        ) {
                            chartType = type
                        }
                    }
                }
            }
        }
    }

    // MARK: - Style Preset Section

    private var stylePresetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style Preset")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(InfographicStylePreset.allCases, id: \.rawValue) { preset in
                        StylePresetButton(
                            preset: preset,
                            isSelected: stylePreset == preset
                        ) {
                            stylePreset = preset
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Input Section

    private var dataInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Data (JSON)")
                    .font(.headline)

                Spacer()

                Button("Use Sample Data") {
                    loadSampleData()
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            if let error = parseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Quick edit section for simple modifications
            if let data = chartData {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Title:")
                            .font(.subheadline)
                        TextField("Chart Title", text: Binding(
                            get: { data.title ?? "" },
                            set: { newTitle in
                                var updatedData = data
                                updatedData.title = newTitle.isEmpty ? nil : newTitle
                                chartData = updatedData
                                jsonText = updatedData.toJSONString() ?? jsonText
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    Text("\(data.items.count) data items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Transform Section

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Position & Scale")
                .font(.headline)

            VStack(spacing: 8) {
                HStack {
                    Text("X Position")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $positionX, in: -0.5...0.5)
                    Text(String(format: "%.2f", positionX))
                        .frame(width: 50)
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Y Position")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $positionY, in: -0.5...0.5)
                    Text(String(format: "%.2f", positionY))
                        .frame(width: 50)
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Scale")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $scale, in: 0.3...1.5)
                    Text(String(format: "%.0f%%", scale * 100))
                        .frame(width: 50)
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)

            ZStack {
                // Background (simulating video frame)
                Color.black
                    .aspectRatio(9/16, contentMode: .fit)

                // Rendered chart
                if let image = renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(CGFloat(scale))
                        .offset(
                            x: CGFloat(positionX) * 150,
                            y: -CGFloat(positionY) * 250
                        )
                } else if chartData == nil {
                    VStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Enter valid JSON to preview")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helper Methods

    private func loadExistingClip() {
        if let clip = viewModel.editingInfographicClip {
            chartType = clip.chartType
            stylePreset = clip.stylePreset
            positionX = clip.positionX
            positionY = clip.positionY
            scale = clip.scale
            if let data = clip.chartData {
                chartData = data
                jsonText = data.toJSONString() ?? ""
            }
        } else {
            loadSampleData()
        }
        updatePreview()
    }

    private func loadSampleData() {
        let sample = ChartData.sample(for: chartType)
        chartData = sample
        jsonText = sample.toJSONString() ?? ""
        parseError = nil
        updatePreview()
    }

    private func parseJSON() {
        guard !jsonText.isEmpty else {
            chartData = nil
            parseError = nil
            renderedImage = nil
            return
        }

        if let data = ChartData.parse(from: jsonText) {
            chartData = data
            parseError = nil
            updatePreview()
        } else {
            parseError = "Invalid JSON format. Check your syntax."
            chartData = nil
            renderedImage = nil
        }
    }

    private func updatePreview() {
        guard let data = chartData else {
            renderedImage = nil
            return
        }

        // Render chart to image
        let previewSize = CGSize(width: 400, height: 300)
        renderedImage = ChartRenderer.shared.renderChart(
            data: data,
            chartType: chartType,
            style: stylePreset,
            size: previewSize
        )
    }

    private func saveInfographic() {
        guard let data = chartData else { return }

        viewModel.saveInfographicClip(
            chartType: chartType,
            stylePreset: stylePreset,
            chartData: data,
            positionX: positionX,
            positionY: positionY,
            scale: scale
        )
        dismiss()
    }
}

// MARK: - Chart Type Button

struct ChartTypeButton: View {
    let type: InfographicChartType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.title2)
                Text(type.displayName)
                    .font(.caption)
            }
            .frame(width: 70, height: 60)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
        }
    }
}

// MARK: - Style Preset Button

struct StylePresetButton: View {
    let preset: InfographicStylePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Color swatch preview
                HStack(spacing: 2) {
                    ForEach(preset.accentColors.prefix(3), id: \.self) { colorHex in
                        Rectangle()
                            .fill(Color(hex: colorHex) ?? .gray)
                            .frame(width: 16, height: 16)
                    }
                }
                .cornerRadius(4)

                Text(preset.displayName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 80)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
        }
        .foregroundColor(.primary)
    }
}

#Preview {
    InfographicsSheet(viewModel: EditorViewModel(project: Project(name: "Test")))
}
