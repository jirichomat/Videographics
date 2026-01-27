//
//  Transition.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia
import AVFoundation

/// Types of transitions available between clips
enum TransitionType: String, Codable, CaseIterable, Identifiable {
    case crossDissolve = "Cross Dissolve"
    case fadeToBlack = "Fade to Black"
    case fadeFromBlack = "Fade from Black"
    case slideLeft = "Slide Left"
    case slideRight = "Slide Right"
    case slideUp = "Slide Up"
    case slideDown = "Slide Down"
    case wipeLeft = "Wipe Left"
    case wipeRight = "Wipe Right"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .crossDissolve: return "circle.lefthalf.filled"
        case .fadeToBlack: return "circle.fill"
        case .fadeFromBlack: return "circle"
        case .slideLeft: return "arrow.left.square"
        case .slideRight: return "arrow.right.square"
        case .slideUp: return "arrow.up.square"
        case .slideDown: return "arrow.down.square"
        case .wipeLeft: return "rectangle.lefthalf.inset.filled.arrow.left"
        case .wipeRight: return "rectangle.righthalf.inset.filled.arrow.right"
        }
    }

    var description: String {
        switch self {
        case .crossDissolve:
            return "Smoothly blend between two clips"
        case .fadeToBlack:
            return "Fade out to black, then show next clip"
        case .fadeFromBlack:
            return "Show first clip, fade in from black to next"
        case .slideLeft:
            return "Next clip slides in from right"
        case .slideRight:
            return "Next clip slides in from left"
        case .slideUp:
            return "Next clip slides in from bottom"
        case .slideDown:
            return "Next clip slides in from top"
        case .wipeLeft:
            return "Wipe reveal from right to left"
        case .wipeRight:
            return "Wipe reveal from left to right"
        }
    }

    /// Default duration for this transition type in seconds
    var defaultDuration: Double {
        switch self {
        case .crossDissolve: return 0.5
        case .fadeToBlack, .fadeFromBlack: return 0.75
        case .slideLeft, .slideRight, .slideUp, .slideDown: return 0.4
        case .wipeLeft, .wipeRight: return 0.5
        }
    }
}

/// Transition between two clips stored in SwiftData
@Model
final class Transition {
    var id: UUID

    // Transition type (stored as raw string for SwiftData)
    var typeRaw: String

    // Duration (CMTime stored as Int64/Int32)
    var durationValue: Int64
    var durationScale: Int32

    // Reference to clips involved (optional, for lookup)
    var fromClipId: UUID?
    var toClipId: UUID?

    init(
        type: TransitionType = .crossDissolve,
        duration: CMTime? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue

        let effectiveDuration = duration ?? CMTime(seconds: type.defaultDuration, preferredTimescale: 600)
        self.durationValue = effectiveDuration.value
        self.durationScale = effectiveDuration.timescale
    }

    // MARK: - Computed Properties

    var type: TransitionType {
        get { TransitionType(rawValue: typeRaw) ?? .crossDissolve }
        set { typeRaw = newValue.rawValue }
    }

    var cmDuration: CMTime {
        CMTime(value: durationValue, timescale: durationScale)
    }

    func setDuration(_ time: CMTime) {
        durationValue = time.value
        durationScale = time.timescale
    }

    /// Duration in seconds
    var durationSeconds: Double {
        cmDuration.seconds
    }
}

// MARK: - Transition Duration Presets

extension Transition {
    static let durationPresets: [(label: String, seconds: Double)] = [
        ("0.25s", 0.25),
        ("0.5s", 0.5),
        ("0.75s", 0.75),
        ("1.0s", 1.0),
        ("1.5s", 1.5),
        ("2.0s", 2.0)
    ]

    /// Minimum allowed transition duration
    static let minDuration: Double = 0.1

    /// Maximum allowed transition duration
    static let maxDuration: Double = 3.0
}
