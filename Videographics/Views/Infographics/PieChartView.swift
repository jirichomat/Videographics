//
//  PieChartView.swift
//  Videographics
//

import SwiftUI

/// SwiftUI view for rendering pie charts
struct PieChartView: View {
    let data: ChartData
    let style: InfographicStylePreset
    let size: CGSize

    private var totalValue: Double {
        data.items.map { $0.value }.reduce(0, +)
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

            HStack(spacing: 20) {
                // Pie chart
                ZStack {
                    ForEach(Array(sliceData.enumerated()), id: \.element.id) { index, slice in
                        PieSlice(
                            startAngle: slice.startAngle,
                            endAngle: slice.endAngle
                        )
                        .fill(sliceColor(for: index, item: slice.item))
                    }
                }
                .frame(width: pieSize, height: pieSize)

                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(data.items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(sliceColor(for: index, item: item))
                                .frame(width: 12, height: 12)

                            Text(item.label)
                                .font(.custom(style.fontName, size: size.width * 0.03))
                                .foregroundColor(textColor)
                                .lineLimit(1)

                            Spacer()

                            Text(formatPercentage(item.value))
                                .font(.custom(style.fontName, size: size.width * 0.03))
                                .fontWeight(.semibold)
                                .foregroundColor(textColor.opacity(0.8))
                        }
                    }
                }
                .frame(maxWidth: size.width * 0.35)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: size.width, height: size.height)
        .background(backgroundColor)
    }

    private var pieSize: CGFloat {
        min(size.width * 0.4, size.height * 0.6)
    }

    private struct SliceData: Identifiable {
        let id: UUID
        let item: ChartData.ChartItem
        let startAngle: Angle
        let endAngle: Angle
    }

    private var sliceData: [SliceData] {
        var currentAngle: Double = -90 // Start from top
        var slices: [SliceData] = []

        for item in data.items {
            let percentage = totalValue > 0 ? item.value / totalValue : 0
            let sliceAngle = percentage * 360

            let slice = SliceData(
                id: item.id,
                item: item,
                startAngle: .degrees(currentAngle),
                endAngle: .degrees(currentAngle + sliceAngle)
            )
            slices.append(slice)
            currentAngle += sliceAngle
        }

        return slices
    }

    private func sliceColor(for index: Int, item: ChartData.ChartItem) -> Color {
        if let customColor = item.color, let color = Color(hex: customColor) {
            return color
        }
        let colors = style.accentColors
        let colorIndex = index % colors.count
        return Color(hex: colors[colorIndex]) ?? .blue
    }

    private func formatPercentage(_ value: Double) -> String {
        guard totalValue > 0 else { return "0%" }
        let percentage = (value / totalValue) * 100
        return String(format: "%.0f%%", percentage)
    }
}

/// Shape for drawing a pie slice
struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

#Preview {
    PieChartView(
        data: ChartData.samplePieChart,
        style: .tikTokNeon,
        size: CGSize(width: 400, height: 300)
    )
}
