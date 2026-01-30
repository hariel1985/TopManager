import SwiftUI
import Charts

struct DownloadLineChart: View {
    let history: [NetworkHistoryPoint]

    var maxRate: Double {
        max(history.map(\.downloadRate).max() ?? 0, 1024)
    }

    var yScaleMax: Double {
        maxRate * 1.1 // 10% margin at top
    }

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Download", point.downloadRate)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: 0...yScaleMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(formatBytesPerSecond(rate))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
            }
        }
        .padding(.vertical, 8)
        .drawingGroup()
    }
}

struct UploadLineChart: View {
    let history: [NetworkHistoryPoint]

    var maxRate: Double {
        max(history.map(\.uploadRate).max() ?? 0, 1024)
    }

    var yScaleMax: Double {
        maxRate * 1.1 // 10% margin at top
    }

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Upload", point.uploadRate)
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: 0...yScaleMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(formatBytesPerSecond(rate))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
            }
        }
        .padding(.vertical, 8)
        .drawingGroup()
    }
}

#Preview {
    VStack {
        DownloadLineChart(history: [])
            .frame(height: 150)
        UploadLineChart(history: [])
            .frame(height: 150)
    }
    .padding()
}
