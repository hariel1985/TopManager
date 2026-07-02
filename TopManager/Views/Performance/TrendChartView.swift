import SwiftUI
import Charts

/// A range selector segmented control used above the live/trend charts.
struct HistoryRangePicker: View {
    @Binding var range: HistoryRange

    var body: some View {
        Picker("", selection: $range) {
            ForEach(HistoryRange.allCases) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Store-backed trend chart. Plots one metric of `MetricsSample` over a chosen
/// window. Used for the non-live ranges (5m / 30m / 1h / 24h).
struct MetricTrendChart: View {
    enum Metric { case cpu, memory, download, upload }

    let samples: [MetricsSample]
    let metric: Metric

    private var color: Color {
        switch metric {
        case .cpu: return .gray
        case .memory: return .purple
        case .download: return .blue
        case .upload: return .green
        }
    }

    private func value(_ s: MetricsSample) -> Double {
        switch metric {
        case .cpu: return s.cpu
        case .memory: return s.memPercent
        case .download: return s.netDown
        case .upload: return s.netUp
        }
    }

    private var isPercent: Bool {
        metric == .cpu || metric == .memory
    }

    private var yDomain: ClosedRange<Double> {
        if isPercent { return -5...105 }
        let maxV = max(samples.map(value).max() ?? 0, 1024)
        return 0...(maxV * 1.1)
    }

    var body: some View {
        Group {
            if samples.isEmpty {
                VStack {
                    Spacer()
                    Text("Collecting history…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(samples) { point in
                        LineMark(
                            x: .value("Time", point.t),
                            y: .value("Value", value(point))
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        AreaMark(
                            x: .value("Time", point.t),
                            y: .value("Value", value(point))
                        )
                        .foregroundStyle(color.opacity(0.12))
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(isPercent ? "\(Int(v))%" : formatBytesPerSecond(v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                    }
                }
                .drawingGroup()
            }
        }
    }
}
