//
//  TextEditorSheet.swift
//  Videographics
//

import SwiftUI

struct TextEditorSheet: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var selectedFont: String = "Helvetica-Bold"
    @State private var fontSize: Float = 48
    @State private var textColor: Color = .white
    @State private var alignment: TextClipAlignment = .center
    @State private var positionX: Float = 0
    @State private var positionY: Float = 0.3  // Slightly above center by default

    private let availableFonts = [
        "Helvetica-Bold",
        "Helvetica",
        "Arial-BoldMT",
        "Arial",
        "Georgia-Bold",
        "Georgia",
        "Courier-Bold",
        "Courier",
        "AmericanTypewriter-Bold",
        "AmericanTypewriter"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Enter text", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Style") {
                    Picker("Font", selection: $selectedFont) {
                        ForEach(availableFonts, id: \.self) { font in
                            Text(fontDisplayName(font))
                                .font(.custom(font, size: 16))
                                .tag(font)
                        }
                    }

                    HStack {
                        Text("Size")
                        Slider(value: $fontSize, in: 16...120, step: 2)
                        Text("\(Int(fontSize))")
                            .frame(width: 40)
                    }

                    ColorPicker("Color", selection: $textColor)

                    Picker("Alignment", selection: $alignment) {
                        Text("Left").tag(TextClipAlignment.left)
                        Text("Center").tag(TextClipAlignment.center)
                        Text("Right").tag(TextClipAlignment.right)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Position") {
                    VStack {
                        Text("Horizontal: \(positionX, specifier: "%.2f")")
                        Slider(value: $positionX, in: -0.8...0.8)
                    }

                    VStack {
                        Text("Vertical: \(positionY, specifier: "%.2f")")
                        Slider(value: $positionY, in: -0.8...0.8)
                    }
                }

                // Preview section
                Section("Preview") {
                    ZStack {
                        Color.black
                            .aspectRatio(9/16, contentMode: .fit)
                            .frame(maxHeight: 200)

                        Text(text.isEmpty ? "Sample Text" : text)
                            .font(.custom(selectedFont, size: CGFloat(fontSize) * 0.3))
                            .foregroundColor(textColor)
                            .multilineTextAlignment(alignment.swiftUIAlignment)
                            .offset(
                                x: CGFloat(positionX) * 50,
                                y: -CGFloat(positionY) * 80
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .navigationTitle(viewModel.editingTextClip == nil ? "Add Text" : "Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveText()
                    }
                    .disabled(text.isEmpty)
                }
            }
            .onAppear {
                loadExistingClip()
            }
        }
    }

    private func fontDisplayName(_ fontName: String) -> String {
        fontName
            .replacingOccurrences(of: "-Bold", with: " Bold")
            .replacingOccurrences(of: "-BoldMT", with: " Bold")
            .replacingOccurrences(of: "MT", with: "")
    }

    private func loadExistingClip() {
        if let clip = viewModel.editingTextClip {
            text = clip.text
            selectedFont = clip.fontName
            fontSize = clip.fontSize
            textColor = clip.textColor
            alignment = clip.alignment
            positionX = clip.positionX
            positionY = clip.positionY
        }
    }

    private func saveText() {
        viewModel.saveTextClip(
            text: text,
            fontName: selectedFont,
            fontSize: fontSize,
            textColorHex: textColor.toHex(),
            alignment: alignment,
            positionX: positionX,
            positionY: positionY
        )
        dismiss()
    }
}

#Preview {
    TextEditorSheet(viewModel: EditorViewModel(project: Project(name: "Test")))
}
