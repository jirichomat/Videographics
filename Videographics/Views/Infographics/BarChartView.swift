//
//  BarChartView.swift
//  Videographics
//

import SwiftUI

/// SwiftUI view for rendering bar charts
struct BarChartView: View {
    let data: ChartData
    let style: InfographicStylePreset
    let size: CGSize

    private var maxValue: Double {
        data.items.map { $0.value }.max() ?? 1
    }

    private var backgroundColor: Color {
        Color(hex: style.backgroundColor) ?? .black
    }

    private var textColor: Color {
        Color(hex: style.primaryTextColor) ?? .white
    }

    var body: some View {
        VStack(spacing: 16) {
            // Title
            if let title = data.title {
                Text(title)
                    .font(.custom(style.fontName, size: size.width * 0.06))
                    .fontWeight(.bold)
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
            }

            // Bars
            HStack(alignment: .bottom, spacing: size.width * 0.03) {
                ForEach(Array(data.items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 8) {
                        // Value label
                        Text(formatValue(item.value))
                            .font(.custom(style.fontName, size: size.width * 0.035))
                            .fontWeight(.semibold)
                            .foregroundColor(textColor)

                        // Bar
                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor(for: index, item: item))
                            .frame(
                                width: barWidth,
                                height: max(barHeight(for: item.value), 10)
                            )

                        // Label
                        Text(item.label)
                            .font(.custom(style.fontName, size: size.width * 0.03))
                            .foregroundColor(textColor.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(width: size.width, height: size.height)
        .background(backgroundColor)
    }

    private var barWidth: CGFloat {
        let count = CGFloat(max(data.items.count, 1))
        let totalSpacing = size.width * 0.03 * (count - 1)
        let availableWidth = size.width - 40 - totalSpacing
        return availableWidth / count
    }

    private var maxBarHeight: CGFloat {
        size.height * 0.5
    }

    private func barHeight(for value: Double) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(value / maxValue) * maxBarHeight
    }

    private func barColor(for index: Int, item: ChartData.ChartItem) -> Color {
        if let customColor = item.color, let color = Color(hex: customColor) {
            return color
        }
        let colors = style.accentColors
        let colorIndex = index % colors.count
        return Color(hex: colors[colorIndex]) ?? .blue
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    BarChartView(
        data: ChartData.sampleBarChart,
        style: .tikTokNeon,
        size: CGSize(width: 400, height: 300)
    )
}
