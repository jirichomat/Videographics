//
//  ChartRenderer.swift
//  Videographics
//

import SwiftUI
import UIKit

/// Service for rendering charts as UIImage for composition
@MainActor
final class ChartRenderer {
    static let shared = ChartRenderer()

    private init() {}

    /// Render a chart as UIImage
    func renderChart(
        data: ChartData,
        chartType: InfographicChartType,
        style: InfographicStylePreset,
        size: CGSize
    ) -> UIImage? {
        let view: any View

        switch chartType {
        case .bar:
            view = BarChartView(data: data, style: style, size: size)
        case .pie:
            view = PieChartView(data: data, style: style, size: size)
        case .line:
            // For MVP, fall back to bar chart
            view = BarChartView(data: data, style: style, size: size)
        case .stat:
            view = StatCardView(data: data, style: style, size: size)
        case .progress:
            view = ProgressBarView(data: data, style: style, size: size)
        case .ranking:
            view = RankingListView(data: data, style: style, size: size)
        }

        let renderer = ImageRenderer(content: AnyView(view))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    /// Render an infographic clip as UIImage
    func renderClip(_ clip: InfographicClip, size: CGSize) -> UIImage? {
        guard let chartData = clip.chartData else { return nil }

        return renderChart(
            data: chartData,
            chartType: clip.chartType,
            style: clip.stylePreset,
            size: size
        )
    }
}

// MARK: - Additional Chart Views for completeness

/// Simple stat card view
struct StatCardView: View {
    let data: ChartData
    let style: InfographicStylePreset
    let size: CGSize

    private var backgroundColor: Color {
        Color(hex: style.backgroundColor) ?? .black
    }

    private var textColor: Color {
        Color(hex: style.primaryTextColor) ?? .white
    }

    private var accentColor: Color {
        Color(hex: style.accentColors.first ?? "#00F5D4") ?? .cyan
    }

    var body: some View {
        VStack(spacing: 12) {
            if let title = data.title {
                Text(title)
                    .font(.custom(style.fontName, size: size.width * 0.04))
                    .foregroundColor(textColor.opacity(0.7))
            }

            if let item = data.items.first {
                Text(formatLargeNumber(item.value))
                    .font(.custom(style.fontName, size: size.width * 0.12))
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)

                if !item.label.isEmpty {
                    Text(item.label)
                        .font(.custom(style.fontName, size: size.width * 0.035))
                        .foregroundColor(textColor.opacity(0.6))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(backgroundColor)
    }

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

/// Progress bar view
struct ProgressBarView: View {
    let data: ChartData
    let style: InfographicStylePreset
    let size: CGSize

    private var backgroundColor: Color {
        Color(hex: style.backgroundColor) ?? .black
    }

    private var textColor: Color {
        Color(hex: style.primaryTextColor) ?? .white
    }

    private var accentColor: Color {
        Color(hex: style.accentColors.first ?? "#00F5D4") ?? .cyan
    }

    private var progress: Double {
        guard let item = data.items.first else { return 0 }
        return min(max(item.value / 100, 0), 1)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let title = data.title {
                Text(title)
                    .font(.custom(style.fontName, size: size.width * 0.05))
                    .fontWeight(.bold)
                    .foregroundColor(textColor)
            }

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 12)
                    .fill(textColor.opacity(0.2))
                    .frame(height: 24)

                // Progress fill
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor)
                    .frame(width: (size.width - 80) * progress, height: 24)
            }
            .frame(width: size.width - 80)

            if let item = data.items.first {
                Text("\(Int(item.value))%")
                    .font(.custom(style.fontName, size: size.width * 0.08))
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(backgroundColor)
    }
}

/// Ranking list view
struct RankingListView: View {
    let data: ChartData
    let style: InfographicStylePreset
    let size: CGSize

    private var backgroundColor: Color {
        Color(hex: style.backgroundColor) ?? .black
    }

    private var textColor: Color {
        Color(hex: style.primaryTextColor) ?? .white
    }

    var body: some View {
        VStack(spacing: 12) {
            if let title = data.title {
                Text(title)
                    .font(.custom(style.fontName, size: size.width * 0.05))
                    .fontWeight(.bold)
                    .foregroundColor(textColor)
            }

            VStack(spacing: 8) {
                ForEach(Array(data.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    HStack {
                        // Rank badge
                        Text("\(index + 1)")
                            .font(.custom(style.fontName, size: size.width * 0.04))
                            .fontWeight(.bold)
                            .foregroundColor(textColor)
                            .frame(width: 30, height: 30)
                            .background(rankColor(for: index))
                            .clipShape(Circle())

                        Text(item.label)
                            .font(.custom(style.fontName, size: size.width * 0.035))
                            .foregroundColor(textColor)

                        Spacer()

                        Text(formatValue(item.value))
                            .font(.custom(style.fontName, size: size.width * 0.035))
                            .fontWeight(.semibold)
                            .foregroundColor(textColor.opacity(0.8))
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(backgroundColor)
    }

    private func rankColor(for index: Int) -> Color {
        let colors = style.accentColors
        let colorIndex = index % colors.count
        return Color(hex: colors[colorIndex]) ?? .blue
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}
