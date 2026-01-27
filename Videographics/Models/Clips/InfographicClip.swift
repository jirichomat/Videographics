//
//  InfographicClip.swift
//  Videographics
//

import Foundation
import SwiftData
import CoreMedia

@Model
final class InfographicClip {
    var id: UUID

    // Chart Configuration
    var chartTypeRaw: String
    var stylePresetRaw: String
    var chartDataJSON: String
    var titleText: String?

    // Transform (normalized -1 to 1, center is 0,0)
    var positionX: Float
    var positionY: Float
    var scale: Float
    var rotation: Float
    var opacity: Float

    // Animation
    var animationDurationSeconds: Float
    var animationDelaySeconds: Float
    var shouldAnimateOnAppear: Bool

    // Timeline position (CMTime stored as Int64/Int32 for SwiftData)
    var timelineStartTimeValue: Int64
    var timelineStartTimeScale: Int32

    // Duration on timeline
    var durationValue: Int64
    var durationScale: Int32

    var layer: InfographicLayer?

    init(
        chartType: InfographicChartType = .bar,
        stylePreset: InfographicStylePreset = .tikTokNeon,
        chartData: ChartData,
        timelineStartTime: CMTime = .zero,
        duration: CMTime = CMTime(seconds: 5.0, preferredTimescale: 600),
        positionX: Float = 0,
        positionY: Float = 0,
        scale: Float = 1.0,
        rotation: Float = 0,
        opacity: Float = 1.0
    ) {
        self.id = UUID()
        self.chartTypeRaw = chartType.rawValue
        self.stylePresetRaw = stylePreset.rawValue
        self.chartDataJSON = chartData.toJSONString() ?? "{}"
        self.titleText = chartData.title

        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity

        self.animationDurationSeconds = 1.0
        self.animationDelaySeconds = 0
        self.shouldAnimateOnAppear = true

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

    // MARK: - Chart Type

    var chartType: InfographicChartType {
        get { InfographicChartType(rawValue: chartTypeRaw) ?? .bar }
        set { chartTypeRaw = newValue.rawValue }
    }

    // MARK: - Style Preset

    var stylePreset: InfographicStylePreset {
        get { InfographicStylePreset(rawValue: stylePresetRaw) ?? .tikTokNeon }
        set { stylePresetRaw = newValue.rawValue }
    }

    // MARK: - Chart Data

    var chartData: ChartData? {
        get { ChartData.parse(from: chartDataJSON) }
        set {
            if let data = newValue {
                chartDataJSON = data.toJSONString() ?? "{}"
                titleText = data.title
            }
        }
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
