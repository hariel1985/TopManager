import SwiftUI
import Charts

struct MemoryLineChart: View {
    let history: [MemoryHistoryPoint]

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.usagePercentage)
                )
                .foregroundStyle(.blue)
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
        .drawingGroup()
    }
}

#Preview {
    MemoryLineChart(history: [])
        .frame(height: 200)
        .padding()
}
