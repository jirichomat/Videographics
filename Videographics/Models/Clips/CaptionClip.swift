//
//  CaptionClip.swift
//  Videographics
//
//  Caption clip model for auto-generated captions with word-level timestamps
//

import Foundation
import SwiftData
import CoreMedia
import SwiftUI

/// Coloring mode for premium caption styles
enum CaptionColoringMode: String, Codable {
    case uniform        // All text same color (boldYellow)
    case perLine        // Alternating line colors (bubbleComic)
    case currentWord    // Currently spoken word highlighted (condensedHeadline)
}

/// Caption display style presets
enum CaptionStyle: String, Codable, CaseIterable {
    case classic          // Static bottom text
    case tiktok           // Animated word-by-word highlight
    case karaoke          // Highlight words as spoken
    case minimal          // Clean sans-serif
    case bold             // Large bold text
    case outline          // Text with outline
    case bubbleComic      // Premium: rounded heavy with stroke/shadow, alternating line colors
    case boldYellow       // Premium: heavy italic gold with hard shadow
    case condensedHeadline // Premium: condensed heavy, current word highlight

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .tiktok: return "TikTok"
        case .karaoke: return "Karaoke"
        case .minimal: return "Minimal"
        case .bold: return "Bold"
        case .outline: return "Outline"
        case .bubbleComic: return "Bubble Comic"
        case .boldYellow: return "Bold Yellow"
        case .condensedHeadline: return "Condensed Headline"
        }
    }

    var defaultFontName: String {
        switch self {
        case .classic, .karaoke: return "Helvetica-Bold"
        case .tiktok, .bold: return "AvenirNext-Heavy"
        case .minimal: return "SFProText-Regular"
        case .outline: return "Helvetica-Bold"
        case .bubbleComic: return "SFRounded-Heavy"  // Sentinel, resolved at render time
        case .boldYellow: return "AvenirNext-HeavyItalic"
        case .condensedHeadline: return "AvenirNextCondensed-Heavy"
        }
    }

    var defaultFontSize: Float {
        switch self {
        case .classic, .minimal: return 36
        case .tiktok, .karaoke: return 42
        case .bold: return 48
        case .outline: return 40
        case .bubbleComic: return 48
        case .boldYellow, .condensedHeadline: return 52
        }
    }

    var defaultTextColor: String {
        switch self {
        case .classic, .minimal, .outline: return "#FFFFFF"
        case .tiktok: return "#FFFF00"
        case .karaoke: return "#00FFFF"
        case .bold: return "#FFFFFF"
        case .bubbleComic: return "#FFFFFF"
        case .boldYellow: return "#F2C100"
        case .condensedHeadline: return "#FFFFFF"
        }
    }

    var defaultHighlightColor: String {
        switch self {
        case .classic, .minimal: return "#FFFF00"
        case .tiktok: return "#FF0080"
        case .karaoke: return "#FF00FF"
        case .bold: return "#FF6600"
        case .outline: return "#00FF00"
        case .bubbleComic: return "#22D5CF"
        case .boldYellow: return "#F2C100"
        case .condensedHeadline: return "#F2C100"
        }
    }

    var hasWordAnimation: Bool {
        switch self {
        case .tiktok, .karaoke: return true
        default: return false
        }
    }

    // MARK: - Premium Renderer Properties

    var usesPremiumRenderer: Bool {
        switch self {
        case .bubbleComic, .boldYellow, .condensedHeadline: return true
        default: return false
        }
    }

    var strokeWidthFraction: CGFloat {
        switch self {
        case .bubbleComic: return 0.14
        case .boldYellow, .condensedHeadline: return 0.10
        default: return 0
        }
    }

    var strokeColorHex: String {
        return "#000000"
    }

    var shadowOffset: CGSize {
        // Values at 1080p reference
        switch self {
        case .bubbleComic: return CGSize(width: 10, height: 12)
        case .boldYellow: return CGSize(width: 14, height: 16)
        case .condensedHeadline: return CGSize(width: 12, height: 14)
        default: return .zero
        }
    }

    var shadowOpacity: Float {
        switch self {
        case .bubbleComic: return 0.55
        case .boldYellow: return 0.70
        case .condensedHeadline: return 0.65
        default: return 0
        }
    }

    var shadowBlurRadius: CGFloat {
        switch self {
        case .bubbleComic: return 8
        case .boldYellow: return 6
        case .condensedHeadline: return 5
        default: return 0
        }
    }

    var lineSpacingMultiplier: CGFloat {
        switch self {
        case .bubbleComic: return 0.78
        case .boldYellow: return 0.74
        case .condensedHeadline: return 0.70
        default: return 1.0
        }
    }

    var fontSizeFraction: CGFloat {
        switch self {
        case .bubbleComic: return 0.057
        case .boldYellow: return 0.068
        case .condensedHeadline: return 0.070
        default: return 0
        }
    }

    var isUppercased: Bool {
        switch self {
        case .bubbleComic, .boldYellow, .condensedHeadline: return true
        default: return false
        }
    }

    var premiumTextAlignment: NSTextAlignment {
        switch self {
        case .condensedHeadline: return .left
        default: return .center
        }
    }

    var defaultMaxWordsPerLine: Int {
        switch self {
        case .bubbleComic, .boldYellow, .condensedHeadline: return 3
        default: return 5
        }
    }

    var defaultPosition: CGPoint {
        switch self {
        case .bubbleComic: return CGPoint(x: 0, y: -0.12)
        case .boldYellow: return CGPoint(x: 0, y: -0.20)
        case .condensedHeadline: return CGPoint(x: -0.72, y: 0.12)
        default: return CGPoint(x: 0, y: -0.7)
        }
    }

    var coloringMode: CaptionColoringMode {
        switch self {
        case .bubbleComic: return .perLine
        case .boldYellow: return .uniform
        case .condensedHeadline: return .currentWord
        default: return .uniform
        }
    }
}

/// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Represents a segment of caption words grouped for display
struct CaptionSegment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var wordStartIndex: Int       // inclusive index into words array
    var wordEndIndex: Int         // exclusive index into words array
    var startTimeOverride: Double? // nil = derive from word timestamps
    var endTimeOverride: Double?   // nil = derive from word timestamps

    func effectiveStartTime(words: [CaptionWord]) -> Double {
        startTimeOverride ?? words[safe: wordStartIndex]?.startTimeSeconds ?? 0
    }
    func effectiveEndTime(words: [CaptionWord]) -> Double {
        endTimeOverride ?? words[safe: wordEndIndex - 1]?.endTimeSeconds ?? 0
    }
    func extractWords(from allWords: [CaptionWord]) -> [CaptionWord] {
        Array(allWords[max(0, wordStartIndex)..<min(wordEndIndex, allWords.count)])
    }
}

/// Represents a single word with timing for captions
struct CaptionWord: Codable, Identifiable, Equatable {
    var id: UUID
    var word: String
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var confidence: Float

    init(word: String, startTime: Double, endTime: Double, confidence: Float = 1.0) {
        self.id = UUID()
        self.word = word
        self.startTimeSeconds = startTime
        self.endTimeSeconds = endTime
        self.confidence = confidence
    }

    init(from recognized: RecognizedWord) {
        self.id = UUID()
        self.word = recognized.word
        self.startTimeSeconds = recognized.startTime
        self.endTimeSeconds = recognized.endTime
        self.confidence = recognized.confidence
    }

    var duration: Double {
        endTimeSeconds - startTimeSeconds
    }
}

@Model
final class CaptionClip {
    var id: UUID

    // Transcription data stored as JSON
    var wordsJSON: String

    // Full text (convenience)
    var fullText: String

    // Language used for transcription
    var languageCode: String

    // Style properties
    var styleRaw: String
    var fontName: String
    var fontSize: Float
    var textColorHex: String
    var highlightColorHex: String
    var backgroundColorHex: String?

    // Position (normalized -1 to 1, center is 0,0)
    var positionX: Float
    var positionY: Float

    // Scale factor (1.0 = 100%)
    var scale: Float

    // Max words per line for wrapping
    var maxWordsPerLine: Int

    // Custom segments JSON (nil = auto-generate from maxWordsPerLine)
    var segmentsJSON: String?

    // Show background box behind text
    var showBackground: Bool

    // Timeline position (CMTime stored as Int64/Int32 for SwiftData)
    var timelineStartTimeValue: Int64
    var timelineStartTimeScale: Int32

    // Duration on timeline
    var durationValue: Int64
    var durationScale: Int32

    var layer: CaptionLayer?

    init(
        words: [CaptionWord],
        fullText: String,
        languageCode: String,
        timelineStartTime: CMTime = .zero,
        duration: CMTime = CMTime(seconds: 5.0, preferredTimescale: 600),
        style: CaptionStyle = .classic,
        fontName: String? = nil,
        fontSize: Float? = nil,
        textColor: String? = nil,
        highlightColor: String? = nil,
        backgroundColor: String? = nil,
        positionX: Float = 0,
        positionY: Float = -0.7,  // Default near bottom
        scale: Float = 1.0,
        maxWordsPerLine: Int = 5,
        showBackground: Bool = true
    ) {
        self.id = UUID()

        // Encode words to JSON
        let encoder = JSONEncoder()
        self.wordsJSON = (try? encoder.encode(words)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        self.fullText = fullText
        self.languageCode = languageCode
        self.styleRaw = style.rawValue
        self.fontName = fontName ?? style.defaultFontName
        self.fontSize = fontSize ?? style.defaultFontSize
        self.textColorHex = textColor ?? style.defaultTextColor
        self.highlightColorHex = highlightColor ?? style.defaultHighlightColor
        self.backgroundColorHex = backgroundColor
        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.maxWordsPerLine = maxWordsPerLine
        self.showBackground = showBackground

        self.timelineStartTimeValue = timelineStartTime.value
        self.timelineStartTimeScale = timelineStartTime.timescale
        self.durationValue = duration.value
        self.durationScale = duration.timescale
    }

    // MARK: - CMTime Computed Properties

    var cmTimelineStartTime: CMTime {
        CMTime(value: timelineStartTimeValue, timescale: timelineStartTimeScale)
    }

    var cmDuration: CMTime {
        CMTime(value: durationValue, timescale: durationScale)
    }

    var cmTimelineEndTime: CMTime {
        CMTimeAdd(cmTimelineStartTime, cmDuration)
    }

    // MARK: - Words Access

    var words: [CaptionWord] {
        get {
            guard let data = wordsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([CaptionWord].self, from: data)) ?? []
        }
        set {
            let encoder = JSONEncoder()
            wordsJSON = (try? encoder.encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }

    // MARK: - Style Access

    var style: CaptionStyle {
        get { CaptionStyle(rawValue: styleRaw) ?? .classic }
        set {
            styleRaw = newValue.rawValue
            // Update defaults if style changes
            fontName = newValue.defaultFontName
            fontSize = newValue.defaultFontSize
            textColorHex = newValue.defaultTextColor
            highlightColorHex = newValue.defaultHighlightColor

            // Apply premium style defaults
            if newValue.usesPremiumRenderer {
                positionX = Float(newValue.defaultPosition.x)
                positionY = Float(newValue.defaultPosition.y)
                showBackground = false
            }
        }
    }

    // MARK: - Color Helpers

    var textColor: Color {
        Color(hex: textColorHex) ?? .white
    }

    var highlightColor: Color {
        Color(hex: highlightColorHex) ?? .yellow
    }

    var backgroundColor: Color? {
        guard let hex = backgroundColorHex else { return nil }
        return Color(hex: hex)
    }

    // MARK: - Setters

    func setTimelineStartTime(_ time: CMTime) {
        timelineStartTimeValue = time.value
        timelineStartTimeScale = time.timescale
    }

    func setDuration(_ time: CMTime) {
        durationValue = time.value
        durationScale = time.timescale
    }

    // MARK: - Word Grouping

    /// Get words visible at a specific time (relative to clip start)
    func wordsAtTime(_ time: CMTime) -> [CaptionWord] {
        let timeSeconds = CMTimeGetSeconds(time)
        return words.filter { word in
            timeSeconds >= word.startTimeSeconds && timeSeconds < word.endTimeSeconds
        }
    }

    /// Get the current word being spoken at a specific time
    func currentWordAtTime(_ time: CMTime) -> CaptionWord? {
        let timeSeconds = CMTimeGetSeconds(time)
        return words.first { word in
            timeSeconds >= word.startTimeSeconds && timeSeconds < word.endTimeSeconds
        }
    }

    /// Group words into lines for display
    func wordsGroupedIntoLines() -> [[CaptionWord]] {
        var lines: [[CaptionWord]] = []
        var currentLine: [CaptionWord] = []

        for word in words {
            currentLine.append(word)
            if currentLine.count >= maxWordsPerLine {
                lines.append(currentLine)
                currentLine = []
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    /// Get text for a specific time range (for rendering segments)
    func textForTimeRange(start: Double, end: Double) -> String {
        let relevantWords = words.filter { word in
            word.endTimeSeconds > start && word.startTimeSeconds < end
        }
        return relevantWords.map { $0.word }.joined(separator: " ")
    }

    // MARK: - Custom Segments

    /// Decoded custom segments (nil = auto-generate)
    var customSegments: [CaptionSegment]? {
        get {
            guard let json = segmentsJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([CaptionSegment].self, from: data)
        }
        set {
            if let segments = newValue {
                let encoder = JSONEncoder()
                segmentsJSON = (try? encoder.encode(segments)).flatMap { String(data: $0, encoding: .utf8) }
            } else {
                segmentsJSON = nil
            }
        }
    }

    // MARK: - Segment Resolution

    /// Returns segments of lines (each segment = array of lines, each line = array of words).
    /// Uses customSegments if set, otherwise auto-generates from maxWordsPerLine + 2-line grouping.
    func resolvedSegments() -> [[[CaptionWord]]] {
        let allWords = words
        guard !allWords.isEmpty else { return [] }

        if let custom = customSegments, !custom.isEmpty {
            // Each custom segment becomes one segment with lines split by maxWordsPerLine
            return custom.map { segment in
                let segWords = segment.extractWords(from: allWords)
                return splitIntoLines(segWords, maxPerLine: maxWordsPerLine)
            }
        } else {
            // Auto-generate: group into lines, then group lines into 2-line segments
            let lines = wordsGroupedIntoLines()
            return groupLinesIntoSegments(lines, linesPerSegment: 2)
        }
    }

    /// Returns segments with pre-computed timing. Each segment ends when the next starts (no overlap).
    func resolvedSegmentsWithTiming() -> [(lines: [[CaptionWord]], startTime: Double, endTime: Double)] {
        let allWords = words
        guard !allWords.isEmpty else { return [] }

        if let custom = customSegments, !custom.isEmpty {
            var result: [(lines: [[CaptionWord]], startTime: Double, endTime: Double)] = []
            for (idx, segment) in custom.enumerated() {
                let segWords = segment.extractWords(from: allWords)
                let lines = splitIntoLines(segWords, maxPerLine: maxWordsPerLine)
                let startTime = segment.effectiveStartTime(words: allWords)
                // End time: use next segment's start if available, else this segment's end
                let endTime: Double
                if idx + 1 < custom.count {
                    endTime = custom[idx + 1].effectiveStartTime(words: allWords)
                } else {
                    endTime = segment.effectiveEndTime(words: allWords)
                }
                result.append((lines: lines, startTime: startTime, endTime: endTime))
            }
            return result
        } else {
            // Auto-generate from lines
            let lines = wordsGroupedIntoLines()
            let segments = groupLinesIntoSegments(lines, linesPerSegment: 2)
            var result: [(lines: [[CaptionWord]], startTime: Double, endTime: Double)] = []
            for (idx, segment) in segments.enumerated() {
                let flatWords = segment.flatMap { $0 }
                guard let first = flatWords.first, let last = flatWords.last else { continue }
                let startTime = first.startTimeSeconds
                let endTime: Double
                if idx + 1 < segments.count,
                   let nextFirst = segments[idx + 1].flatMap({ $0 }).first {
                    endTime = nextFirst.startTimeSeconds
                } else {
                    endTime = last.endTimeSeconds
                }
                result.append((lines: segment, startTime: startTime, endTime: endTime))
            }
            return result
        }
    }

    /// Generate CaptionSegment objects from current auto-splitting (for seeding the editor)
    func generateAutoSegments() -> [CaptionSegment] {
        let allWords = words
        guard !allWords.isEmpty else { return [] }

        let lines = wordsGroupedIntoLines()
        let lineSegments = groupLinesIntoSegments(lines, linesPerSegment: 2)

        var result: [CaptionSegment] = []
        var wordIndex = 0

        for segment in lineSegments {
            let wordCount = segment.flatMap { $0 }.count
            let seg = CaptionSegment(
                wordStartIndex: wordIndex,
                wordEndIndex: wordIndex + wordCount
            )
            result.append(seg)
            wordIndex += wordCount
        }

        return result
    }

    // MARK: - Private Helpers

    private func splitIntoLines(_ words: [CaptionWord], maxPerLine: Int) -> [[CaptionWord]] {
        var lines: [[CaptionWord]] = []
        var current: [CaptionWord] = []
        for word in words {
            current.append(word)
            if current.count >= maxPerLine {
                lines.append(current)
                current = []
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func groupLinesIntoSegments(_ lines: [[CaptionWord]], linesPerSegment: Int) -> [[[CaptionWord]]] {
        var segments: [[[CaptionWord]]] = []
        var current: [[CaptionWord]] = []
        for line in lines {
            current.append(line)
            if current.count >= linesPerSegment {
                segments.append(current)
                current = []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}
