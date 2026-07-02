import SwiftUI

/// System Health summary card: a 0–100 score, rating, and plain-language
/// diagnosis of what (if anything) is wrong right now.
struct HealthCardView: View {
    @EnvironmentObject var alertCenter: AlertCenter

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 20) {
                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(alertCenter.healthScore) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(alertCenter.healthScore)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(HealthModel.rating(alertCenter.healthScore))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("System Health", systemImage: "heart.text.square")
                            .font(.headline)
                        Spacer()
                        if alertCenter.activeAlertCount > 0 {
                            Label("\(alertCenter.activeAlertCount) active", systemImage: "bell.badge.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    if alertCenter.diagnosis.isEmpty {
                        Label("Everything looks healthy.", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundColor(.green)
                    } else {
                        ForEach(alertCenter.diagnosis, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scoreColor: Color {
        switch alertCenter.healthScore {
        case 85...: return .green
        case 70..<85: return .mint
        case 50..<70: return .orange
        default: return .red
        }
    }
}

/// Inbox of recent alerts fired by the AlertCenter.
struct AlertsInboxView: View {
    @EnvironmentObject var alertCenter: AlertCenter

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Recent Alerts", systemImage: "bell")
                        .font(.headline)
                    Spacer()
                    if !alertCenter.alerts.isEmpty {
                        Button("Clear") { alertCenter.clearInbox() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }

                if alertCenter.alerts.isEmpty {
                    Text("No alerts. TopManager will notify you if something needs attention.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(alertCenter.alerts.prefix(8)) { alert in
                        AlertRowView(alert: alert)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct AlertRowView: View {
    let alert: SystemAlert

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: alert.severity.symbol)
                .foregroundColor(severityColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.title).fontWeight(.medium)
                    Spacer()
                    Text(alert.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Divider()
    }

    private var severityColor: Color {
        switch alert.severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
