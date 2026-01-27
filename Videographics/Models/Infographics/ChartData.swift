//
//  ChartData.swift
//  Videographics
//

import Foundation

/// Chart types available for infographics
enum InfographicChartType: String, Codable, CaseIterable {
    case bar
    case pie
    case line
    case stat
    case progress
    case ranking

    var displayName: String {
        switch self {
        case .bar: return "Bar"
        case .pie: return "Pie"
        case .line: return "Line"
        case .stat: return "Stat"
        case .progress: return "Progress"
        case .ranking: return "Ranking"
        }
    }

    var iconName: String {
        switch self {
        case .bar: return "chart.bar.fill"
        case .pie: return "chart.pie.fill"
        case .line: return "chart.line.uptrend.xyaxis"
        case .stat: return "number"
        case .progress: return "gauge.with.dots.needle.bottom.50percent"
        case .ranking: return "list.number"
        }
    }
}

/// Style presets for chart rendering
enum InfographicStylePreset: String, Codable, CaseIterable {
    case tikTokNeon = "tiktok-neon"
    case instagramClean = "instagram-clean"
    case storyGradient = "story-gradient"
    case youtubePro = "youtube-pro"

    var displayName: String {
        switch self {
        case .tikTokNeon: return "TikTok Neon"
        case .instagramClean: return "Instagram Clean"
        case .storyGradient: return "Story Gradient"
        case .youtubePro: return "YouTube Pro"
        }
    }

    var backgroundColor: String {
        switch self {
        case .tikTokNeon: return "#0D0D0D"
        case .instagramClean: return "#FFFFFF"
        case .storyGradient: return "#1A1A2E"
        case .youtubePro: return "#181818"
        }
    }

    var primaryTextColor: String {
        switch self {
        case .tikTokNeon: return "#FFFFFF"
        case .instagramClean: return "#262626"
        case .storyGradient: return "#FFFFFF"
        case .youtubePro: return "#FFFFFF"
        }
    }

    var accentColors: [String] {
        switch self {
        case .tikTokNeon:
            return ["#00F5D4", "#FF006E", "#7B2CBF", "#00BBF9", "#F15BB5"]
        case .instagramClean:
            return ["#405DE6", "#5851DB", "#833AB4", "#C13584", "#E1306C"]
        case .storyGradient:
            return ["#667EEA", "#764BA2", "#F093FB", "#F5576C", "#4FACFE"]
        case .youtubePro:
            return ["#FF0000", "#FF4444", "#FF6B6B", "#4ECDC4", "#45B7D1"]
        }
    }

    var fontName: String {
        switch self {
        case .tikTokNeon: return "Helvetica-Bold"
        case .instagramClean: return "HelveticaNeue"
        case .storyGradient: return "AvenirNext-DemiBold"
        case .youtubePro: return "Roboto-Medium"
        }
    }
}

/// Data structure for charts
struct ChartData: Codable, Equatable {
    var title: String?
    var items: [ChartItem]

    struct ChartItem: Codable, Equatable, Identifiable {
        var id: UUID
        var label: String
        var value: Double
        var color: String?

        init(id: UUID = UUID(), label: String, value: Double, color: String? = nil) {
            self.id = id
            self.label = label
            self.value = value
            self.color = color
        }
    }

    init(title: String? = nil, items: [ChartItem]) {
        self.title = title
        self.items = items
    }

    /// Parse JSON string to ChartData
    static func parse(from jsonString: String) -> ChartData? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChartData.self, from: data)
    }

    /// Convert to JSON string
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Sample data for bar chart
    static var sampleBarChart: ChartData {
        ChartData(
            title: "Monthly Sales",
            items: [
                ChartItem(label: "Jan", value: 45),
                ChartItem(label: "Feb", value: 62),
                ChartItem(label: "Mar", value: 78),
                ChartItem(label: "Apr", value: 55),
                ChartItem(label: "May", value: 89)
            ]
        )
    }

    /// Sample data for pie chart
    static var samplePieChart: ChartData {
        ChartData(
            title: "Market Share",
            items: [
                ChartItem(label: "Product A", value: 35),
                ChartItem(label: "Product B", value: 25),
                ChartItem(label: "Product C", value: 20),
                ChartItem(label: "Product D", value: 15),
                ChartItem(label: "Other", value: 5)
            ]
        )
    }

    /// Sample data for line chart
    static var sampleLineChart: ChartData {
        ChartData(
            title: "Growth Trend",
            items: [
                ChartItem(label: "Week 1", value: 100),
                ChartItem(label: "Week 2", value: 150),
                ChartItem(label: "Week 3", value: 130),
                ChartItem(label: "Week 4", value: 200),
                ChartItem(label: "Week 5", value: 180),
                ChartItem(label: "Week 6", value: 250)
            ]
        )
    }

    /// Sample data for stat display
    static var sampleStat: ChartData {
        ChartData(
            title: "Total Revenue",
            items: [
                ChartItem(label: "USD", value: 1250000)
            ]
        )
    }

    /// Sample data for progress bar
    static var sampleProgress: ChartData {
        ChartData(
            title: "Goal Progress",
            items: [
                ChartItem(label: "Completed", value: 75)
            ]
        )
    }

    /// Sample data for ranking
    static var sampleRanking: ChartData {
        ChartData(
            title: "Top Performers",
            items: [
                ChartItem(label: "Alice", value: 950),
                ChartItem(label: "Bob", value: 875),
                ChartItem(label: "Charlie", value: 820),
                ChartItem(label: "Diana", value: 780),
                ChartItem(label: "Eve", value: 725)
            ]
        )
    }

    /// Get sample data for a specific chart type
    static func sample(for chartType: InfographicChartType) -> ChartData {
        switch chartType {
        case .bar: return sampleBarChart
        case .pie: return samplePieChart
        case .line: return sampleLineChart
        case .stat: return sampleStat
        case .progress: return sampleProgress
        case .ranking: return sampleRanking
        }
    }
}
