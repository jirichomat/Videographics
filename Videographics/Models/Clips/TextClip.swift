//
//  TextClip.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia
import SwiftUI
import UIKit

/// Text alignment options
enum TextClipAlignment: String, Codable, CaseIterable {
    case left
    case center
    case right

    var swiftUIAlignment: SwiftUI.TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

@Model
final class TextClip {
    var id: UUID

    // Text content
    var text: String

    // Font properties
    var fontName: String
    var fontSize: Float

    // Color stored as hex string (e.g., "#FFFFFF")
    var textColorHex: String
    var backgroundColorHex: String?

    // Alignment
    var alignmentRaw: String

    // Position (normalized -1 to 1, center is 0,0)
    var positionX: Float
    var positionY: Float

    // Scale factor (1.0 = 100%)
    var scale: Float

    // Rotation in degrees
    var rotation: Float

    // Timeline position (CMTime stored as Int64/Int32 for SwiftData)
    var timelineStartTimeValue: Int64
    var timelineStartTimeScale: Int32

    // Duration on timeline
    var durationValue: Int64
    var durationScale: Int32

    var layer: TextLayer?

    init(
        text: String,
        timelineStartTime: CMTime = .zero,
        duration: CMTime = CMTime(seconds: 5.0, preferredTimescale: 600),
        fontName: String = "Helvetica-Bold",
        fontSize: Float = 48,
        textColor: String = "#FFFFFF",
        backgroundColor: String? = nil,
        alignment: TextClipAlignment = .center,
        positionX: Float = 0,
        positionY: Float = 0
    ) {
        self.id = UUID()
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColorHex = textColor
        self.backgroundColorHex = backgroundColor
        self.alignmentRaw = alignment.rawValue
        self.positionX = positionX
        self.positionY = positionY
        self.scale = 1.0
        self.rotation = 0

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

    // MARK: - Alignment

    var alignment: TextClipAlignment {
        get { TextClipAlignment(rawValue: alignmentRaw) ?? .center }
        set { alignmentRaw = newValue.rawValue }
    }

    // MARK: - Color Helpers

    var textColor: Color {
        Color(hex: textColorHex) ?? .white
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
}

// MARK: - Color Extension for Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        } else if length == 8 {
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else { return "#FFFFFF" }
        let r = Int(components[0] * 255)
        let g = Int(components.count > 1 ? components[1] * 255 : components[0] * 255)
        let b = Int(components.count > 2 ? components[2] * 255 : components[0] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
