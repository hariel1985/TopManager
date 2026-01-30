import SwiftUI
import Charts

struct CPULineChart: View {
    let history: [CPUHistoryPoint]

    var body: some View {
        Chart {
            ForEach(history) { point in
                // User usage line
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("User", point.userUsage),
                    series: .value("Type", "User")
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                // System usage line
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("System", point.systemUsage),
                    series: .value("Type", "System")
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                // Total usage line
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Total", point.usage),
                    series: .value("Type", "Total")
                )
                .foregroundStyle(.gray)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: -5...105)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
            }
        }
        .chartLegend(position: .bottom, spacing: 10) {
            HStack(spacing: 16) {
                ChartLegendItem(color: .blue, label: "User")
                ChartLegendItem(color: .red, label: "System")
                ChartLegendItem(color: .gray, label: "Total")
            }
        }
        .drawingGroup()
    }
}

struct ChartLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    CPULineChart(history: [])
        .frame(height: 200)
        .padding()
}
