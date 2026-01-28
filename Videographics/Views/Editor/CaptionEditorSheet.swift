//
//  CaptionEditorSheet.swift
//  Videographics
//
//  UI for auto-captions: transcription, editing, and styling
//

import SwiftUI
import CoreMedia

struct CaptionEditorSheet: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    // Speech recognition
    @StateObject private var speechService = SpeechRecognitionService.shared

    // Source selection
    @State private var selectedVideoClip: VideoClip?

    // Language
    @State private var selectedLanguage: SpeechLanguage = .czech

    // Transcription state
    @State private var transcriptionResult: TranscriptionResult?
    @State private var editedWords: [CaptionWord] = []
    @State private var editedText: String = ""

    // Segments
    @State private var editedSegments: [CaptionSegment] = []
    @State private var selectedSegmentIndex: Int? = nil

    // Style options
    @State private var selectedStyle: CaptionStyle = .classic
    @State private var fontSize: Float = 36
    @State private var textColor: Color = .white
    @State private var highlightColor: Color = .yellow
    @State private var positionX: Float = 0
    @State private var positionY: Float = -0.7
    @State private var scale: Float = 1.0
    @State private var maxWordsPerLine: Int = 5
    @State private var showBackground: Bool = true

    // UI state
    @State private var showingLanguagePicker = false
    @State private var showingClipPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // Source selection
                sourceSection

                // Language selection
                languageSection

                // Transcription section
                if speechService.isTranscribing {
                    transcribingSection
                } else if transcriptionResult != nil {
                    transcriptionSection
                    styleSection
                    positionSection
                    previewSection
                }

                // Error display
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(viewModel.editingCaptionClip == nil ? "Auto Captions" : "Edit Captions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speechService.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCaption()
                    }
                    .disabled(editedWords.isEmpty)
                }
            }
            .onAppear {
                loadExistingClip()
                setupDefaultVideoClip()
            }
        }
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        Section("Source Video") {
            if let clip = selectedVideoClip {
                HStack {
                    // Thumbnail
                    if let thumbData = clip.thumbnails.first,
                       let uiImage = UIImage(data: thumbData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 80)
                    }

                    VStack(alignment: .leading) {
                        Text("Selected Clip")
                            .font(.headline)
                        Text(formatDuration(clip.cmDuration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No video clips available")
                    .foregroundColor(.secondary)
            }

            if transcriptionResult == nil && !speechService.isTranscribing {
                Button {
                    startTranscription()
                } label: {
                    Label("Generate Captions", systemImage: "waveform")
                }
                .disabled(selectedVideoClip == nil)
            }
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: $selectedLanguage) {
                ForEach(speechService.availableLanguages()) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            }
            .disabled(speechService.isTranscribing)
        }
    }

    // MARK: - Transcribing Section

    private var transcribingSection: some View {
        Section("Transcribing...") {
            VStack(spacing: 12) {
                ProgressView(value: speechService.progress)
                    .progressViewStyle(LinearProgressViewStyle())

                Text("\(Int(speechService.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Cancel") {
                    speechService.cancel()
                }
                .foregroundColor(.red)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        Section("Segments") {
            // Word count
            HStack {
                Text("Words detected")
                Spacer()
                Text("\(editedWords.count)")
                    .foregroundColor(.secondary)
            }

            // Words per segment stepper
            Stepper("Words per Segment: \(maxWordsPerLine * 2)", value: $maxWordsPerLine, in: 2...10)
                .onChange(of: maxWordsPerLine) { _, _ in
                    regenerateSegments()
                }

            // Segment mini-timeline
            if !editedSegments.isEmpty {
                segmentTimelineView
            }

            // Segment list
            if !editedSegments.isEmpty {
                segmentListView
            }

            // Selected segment editor
            if let idx = selectedSegmentIndex, idx < editedSegments.count {
                selectedSegmentEditor(index: idx)
            }

            // Re-transcribe button
            Button {
                startTranscription()
            } label: {
                Label("Re-transcribe", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Segment Timeline View

    private var segmentTimelineView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Segment Timeline")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(editedSegments.enumerated()), id: \.element.id) { index, segment in
                        let duration = segmentDuration(segment, index: index)
                        let totalDuration = totalSegmentsDuration()
                        let widthFraction = totalDuration > 0 ? duration / totalDuration : 1.0 / Double(editedSegments.count)

                        Button {
                            selectedSegmentIndex = index
                        } label: {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedSegmentIndex == index ? Color.blue : Color.gray.opacity(0.6))
                                )
                        }
                        .frame(width: max(30, CGFloat(widthFraction) * 280))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Segment List View

    private var segmentListView: some View {
        VStack(spacing: 0) {
            ForEach(Array(editedSegments.enumerated()), id: \.element.id) { index, segment in
                let words = segment.extractWords(from: editedWords)
                let preview = words.prefix(6).map { $0.word }.joined(separator: " ")
                let startTime = segment.effectiveStartTime(words: editedWords)
                let endTime = segmentEndTime(index: index, segment: segment)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Segment \(index + 1)")
                                .font(.caption.bold())
                            Text(preview + (words.count > 6 ? "..." : ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text("\(formatSeconds(startTime)) — \(formatSeconds(endTime))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Split button
                        if words.count > 1 {
                            Button {
                                splitSegment(at: index)
                            } label: {
                                Image(systemName: "scissors")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        // Merge with next button
                        if index < editedSegments.count - 1 {
                            Button {
                                mergeSegment(at: index)
                            } label: {
                                Image(systemName: "arrow.right.arrow.left")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .background(selectedSegmentIndex == index ? Color.blue.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSegmentIndex = index
                    }

                    if index < editedSegments.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Selected Segment Editor

    @ViewBuilder
    private func selectedSegmentEditor(index: Int) -> some View {
        let segment = editedSegments[index]
        let words = segment.extractWords(from: editedWords)
        let text = words.map { $0.word }.joined(separator: " ")
        let startTime = segment.effectiveStartTime(words: editedWords)
        let endTime = segmentEndTime(index: index, segment: segment)

        VStack(alignment: .leading, spacing: 8) {
            Text("Segment \(index + 1) Details")
                .font(.caption.bold())

            // Full text display
            Text(text)
                .font(.body)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(6)

            // Timing adjustments
            HStack {
                VStack(alignment: .leading) {
                    Text("Start")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Button {
                            adjustSegmentStartTime(index: index, delta: -0.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Text(formatSeconds(startTime))
                            .font(.caption.monospacedDigit())
                            .frame(width: 50)

                        Button {
                            adjustSegmentStartTime(index: index, delta: 0.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("End")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Button {
                            adjustSegmentEndTime(index: index, delta: -0.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Text(formatSeconds(endTime))
                            .font(.caption.monospacedDigit())
                            .frame(width: 50)

                        Button {
                            adjustSegmentEndTime(index: index, delta: 0.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Style Section

    private var styleSection: some View {
        Section("Style") {
            Picker("Style Preset", selection: $selectedStyle) {
                ForEach(CaptionStyle.allCases, id: \.self) { style in
                    Text(style.displayName)
                        .tag(style)
                }
            }
            .onChange(of: selectedStyle) { _, newStyle in
                applyStyleDefaults(newStyle)
            }

            if !selectedStyle.usesPremiumRenderer {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(fontSize))")
                        .foregroundColor(.secondary)
                }
                Slider(value: $fontSize, in: 24...72, step: 2)

                ColorPicker("Text Color", selection: $textColor)
                ColorPicker("Highlight Color", selection: $highlightColor)

                Toggle("Show Background", isOn: $showBackground)
            }
        }
    }

    // MARK: - Position Section

    private var positionSection: some View {
        Section("Position") {
            VStack {
                HStack {
                    Text("Horizontal")
                    Spacer()
                    Text(positionX == 0 ? "Center" : String(format: "%.1f", positionX))
                        .foregroundColor(.secondary)
                }
                Slider(value: $positionX, in: -0.8...0.8)
            }

            VStack {
                HStack {
                    Text("Vertical")
                    Spacer()
                    Text(positionY < 0 ? "Bottom" : positionY > 0 ? "Top" : "Center")
                        .foregroundColor(.secondary)
                }
                Slider(value: $positionY, in: -0.9...0.9)
            }

            VStack {
                HStack {
                    Text("Scale")
                    Spacer()
                    Text("\(Int(scale * 100))%")
                        .foregroundColor(.secondary)
                }
                Slider(value: $scale, in: 0.5...2.0)
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section("Preview") {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black)

                    if selectedStyle.usesPremiumRenderer {
                        // Premium preview using PremiumCaptionRenderer
                        premiumPreviewImage(in: geometry.size)
                    } else {
                        // Standard text preview
                        VStack {
                            if showBackground {
                                Text(previewText)
                                    .font(.system(size: CGFloat(fontSize * scale * 0.5)))
                                    .foregroundColor(textColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                            } else {
                                Text(previewText)
                                    .font(.system(size: CGFloat(fontSize * scale * 0.5)))
                                    .foregroundColor(textColor)
                            }
                        }
                        .position(
                            x: geometry.size.width / 2 + CGFloat(positionX) * geometry.size.width / 2,
                            y: geometry.size.height / 2 - CGFloat(positionY) * geometry.size.height / 2
                        )
                    }
                }
            }
            .frame(height: 200)
            .aspectRatio(9/16, contentMode: .fit)
        }
    }

    @ViewBuilder
    private func premiumPreviewImage(in size: CGSize) -> some View {
        let sampleLines = [previewText]
        let renderSize = CGSize(width: 1080, height: 1920)
        let config = PremiumRenderConfig(
            lines: sampleLines,
            style: selectedStyle,
            renderSize: renderSize,
            textColorHex: selectedStyle.defaultTextColor,
            highlightColorHex: selectedStyle.defaultHighlightColor,
            fontName: selectedStyle.defaultFontName,
            scale: scale
        )

        if let cgImage = PremiumCaptionRenderer.render(config: config) {
            let uiImage = UIImage(cgImage: cgImage)
            let previewScale = size.width / renderSize.width
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: CGFloat(uiImage.size.width) * previewScale,
                    height: CGFloat(uiImage.size.height) * previewScale
                )
                .position(
                    x: size.width / 2 + CGFloat(positionX) * size.width / 2,
                    y: size.height / 2 - CGFloat(positionY) * size.height / 2
                )
        }
    }

    private var previewText: String {
        let words = editedWords.prefix(maxWordsPerLine)
        if words.isEmpty {
            return "Sample caption text"
        }
        return words.map { $0.word }.joined(separator: " ")
    }

    // MARK: - Actions

    private func loadExistingClip() {
        if let clip = viewModel.editingCaptionClip {
            editedWords = clip.words
            editedText = clip.fullText
            selectedStyle = clip.style
            fontSize = clip.fontSize
            textColor = clip.textColor
            highlightColor = clip.highlightColor
            positionX = clip.positionX
            positionY = clip.positionY
            scale = clip.scale
            maxWordsPerLine = clip.maxWordsPerLine
            showBackground = clip.showBackground

            // Load custom segments if present, otherwise seed from auto
            if let custom = clip.customSegments, !custom.isEmpty {
                editedSegments = custom
            } else {
                editedSegments = clip.generateAutoSegments()
            }

            // Set language
            if let lang = SpeechLanguage(rawValue: clip.languageCode) {
                selectedLanguage = lang
            }

            // Create a mock transcription result for editing
            transcriptionResult = TranscriptionResult(
                words: editedWords.map { RecognizedWord(
                    word: $0.word,
                    startTime: $0.startTimeSeconds,
                    endTime: $0.endTimeSeconds,
                    confidence: $0.confidence
                )},
                fullText: clip.fullText,
                language: clip.languageCode,
                duration: clip.cmDuration.seconds
            )
        }
    }

    private func setupDefaultVideoClip() {
        // Select the first video clip if none selected
        if selectedVideoClip == nil,
           let timeline = viewModel.project.timeline,
           let mainLayer = timeline.mainVideoLayer {
            selectedVideoClip = mainLayer.clips.first
        }
    }

    private func startTranscription() {
        guard let clip = selectedVideoClip,
              let url = clip.assetURL else {
            errorMessage = "No video clip selected"
            return
        }

        errorMessage = nil

        Task {
            do {
                let result = try await speechService.transcribe(
                    videoURL: url,
                    language: selectedLanguage
                )
                transcriptionResult = result
                editedWords = result.words.map { CaptionWord(from: $0) }
                editedText = result.fullText

                // Auto-generate segments from the new transcription
                regenerateSegments()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyStyleDefaults(_ style: CaptionStyle) {
        fontSize = style.defaultFontSize
        textColor = Color(hex: style.defaultTextColor) ?? .white
        highlightColor = Color(hex: style.defaultHighlightColor) ?? .yellow

        // Apply premium style defaults
        if style.usesPremiumRenderer {
            positionX = Float(style.defaultPosition.x)
            positionY = Float(style.defaultPosition.y)
            showBackground = false
        }

        // Apply default words per line
        maxWordsPerLine = style.defaultMaxWordsPerLine
    }

    private func saveCaption() {
        guard !editedWords.isEmpty else { return }

        // Calculate duration from words
        let minStart = editedWords.map { $0.startTimeSeconds }.min() ?? 0
        let maxEnd = editedWords.map { $0.endTimeSeconds }.max() ?? 5.0
        let duration = CMTime(seconds: maxEnd - minStart, preferredTimescale: 600)

        // Determine start time
        let startTime: CMTime
        if let clip = selectedVideoClip {
            // Align with video clip start
            startTime = clip.cmTimelineStartTime
        } else {
            startTime = viewModel.currentTime
        }

        viewModel.saveCaptionClip(
            words: editedWords,
            fullText: editedText,
            languageCode: selectedLanguage.rawValue,
            style: selectedStyle,
            fontSize: fontSize,
            textColorHex: textColor.toHex(),
            highlightColorHex: highlightColor.toHex(),
            positionX: positionX,
            positionY: positionY,
            scale: scale,
            maxWordsPerLine: maxWordsPerLine,
            showBackground: showBackground,
            timelineStartTime: startTime,
            duration: duration,
            customSegments: editedSegments.isEmpty ? nil : editedSegments
        )
        dismiss()
    }

    // MARK: - Segment Manipulation

    /// Regenerate segments from current words and maxWordsPerLine
    private func regenerateSegments() {
        guard !editedWords.isEmpty else {
            editedSegments = []
            return
        }

        // Build a temporary CaptionClip to use its auto-generation
        let linesPerSegment = 2
        let wordsPerSegment = maxWordsPerLine * linesPerSegment
        var segments: [CaptionSegment] = []
        var wordIndex = 0

        while wordIndex < editedWords.count {
            let endIndex = min(wordIndex + wordsPerSegment, editedWords.count)
            segments.append(CaptionSegment(
                wordStartIndex: wordIndex,
                wordEndIndex: endIndex
            ))
            wordIndex = endIndex
        }

        editedSegments = segments
        selectedSegmentIndex = nil
    }

    /// Split a segment at the midpoint word index
    private func splitSegment(at index: Int) {
        guard index < editedSegments.count else { return }
        let segment = editedSegments[index]
        let wordCount = segment.wordEndIndex - segment.wordStartIndex
        guard wordCount > 1 else { return }

        let midpoint = segment.wordStartIndex + wordCount / 2

        let first = CaptionSegment(
            wordStartIndex: segment.wordStartIndex,
            wordEndIndex: midpoint,
            startTimeOverride: segment.startTimeOverride,
            endTimeOverride: nil
        )
        let second = CaptionSegment(
            wordStartIndex: midpoint,
            wordEndIndex: segment.wordEndIndex,
            startTimeOverride: nil,
            endTimeOverride: segment.endTimeOverride
        )

        editedSegments.replaceSubrange(index...index, with: [first, second])
        selectedSegmentIndex = index
    }

    /// Merge segment at index with the next segment
    private func mergeSegment(at index: Int) {
        guard index < editedSegments.count - 1 else { return }
        let first = editedSegments[index]
        let second = editedSegments[index + 1]

        let merged = CaptionSegment(
            wordStartIndex: first.wordStartIndex,
            wordEndIndex: second.wordEndIndex,
            startTimeOverride: first.startTimeOverride,
            endTimeOverride: second.endTimeOverride
        )

        editedSegments.replaceSubrange(index...(index + 1), with: [merged])
        selectedSegmentIndex = index
    }

    /// Adjust segment start time override
    private func adjustSegmentStartTime(index: Int, delta: Double) {
        guard index < editedSegments.count else { return }
        let current = editedSegments[index].effectiveStartTime(words: editedWords)
        let newTime = max(0, current + delta)
        editedSegments[index].startTimeOverride = newTime
    }

    /// Adjust segment end time override
    private func adjustSegmentEndTime(index: Int, delta: Double) {
        guard index < editedSegments.count else { return }
        let current: Double
        if index + 1 < editedSegments.count {
            current = editedSegments[index + 1].effectiveStartTime(words: editedWords)
            // Adjusting end time of this segment = adjusting start time of next
            let newTime = max(0, current + delta)
            editedSegments[index + 1].startTimeOverride = newTime
        } else {
            current = editedSegments[index].effectiveEndTime(words: editedWords)
            let newTime = max(0, current + delta)
            editedSegments[index].endTimeOverride = newTime
        }
    }

    // MARK: - Segment Timing Helpers

    /// Get end time for a segment at a given index
    private func segmentEndTime(index: Int, segment: CaptionSegment) -> Double {
        if index + 1 < editedSegments.count {
            return editedSegments[index + 1].effectiveStartTime(words: editedWords)
        } else {
            return segment.effectiveEndTime(words: editedWords)
        }
    }

    private func segmentDuration(_ segment: CaptionSegment, index: Int) -> Double {
        let start = segment.effectiveStartTime(words: editedWords)
        let end: Double
        if index + 1 < editedSegments.count {
            end = editedSegments[index + 1].effectiveStartTime(words: editedWords)
        } else {
            end = segment.effectiveEndTime(words: editedWords)
        }
        return max(0.1, end - start)
    }

    private func totalSegmentsDuration() -> Double {
        guard let first = editedSegments.first, let last = editedSegments.last else { return 0 }
        let start = first.effectiveStartTime(words: editedWords)
        let end = last.effectiveEndTime(words: editedWords)
        return max(0.1, end - start)
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }

    private func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
