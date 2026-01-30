import SwiftUI

struct MemoryDonutView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var memorySegments: [MemorySegment] {
        guard let mem = monitor.memoryInfo else { return [] }

        return [
            MemorySegment(name: "App", value: Double(mem.appMemory), color: .blue),
            MemorySegment(name: "Wired", value: Double(mem.wiredMemory), color: .orange),
            MemorySegment(name: "Compressed", value: Double(mem.compressedMemory), color: .yellow),
            MemorySegment(name: "Free", value: Double(mem.freeMemory + mem.cachedMemory), color: .green.opacity(0.5))
        ]
    }

    var body: some View {
        ZStack {
            // Donut chart
            DonutChart(segments: memorySegments)

            // Center text
            if let mem = monitor.memoryInfo {
                VStack {
                    Text(formatBytes(mem.usedMemory))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("of \(formatBytes(mem.totalMemory))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct DonutChart: View {
    let segments: [MemorySegment]
    let lineWidth: CGFloat = 30

    var total: Double {
        segments.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    DonutSegment(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        lineWidth: lineWidth
                    )
                    .fill(segment.color)
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func startAngle(for index: Int) -> Angle {
        guard total > 0 else { return .degrees(-90) }
        let precedingSum = segments.prefix(index).reduce(0) { $0 + $1.value }
        return .degrees((precedingSum / total) * 360 - 90)
    }

    private func endAngle(for index: Int) -> Angle {
        guard total > 0 else { return .degrees(-90) }
        let sum = segments.prefix(index + 1).reduce(0) { $0 + $1.value }
        return .degrees((sum / total) * 360 - 90)
    }
}

struct DonutSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2

        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }
}

struct MemorySegment: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

#Preview {
    MemoryDonutView()
        .environmentObject(SystemMonitor.shared)
        .frame(width: 250, height: 250)
        .padding()
}
