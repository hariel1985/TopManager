import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 440, height: 340)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Text(String(format: "%.0f s", settings.refreshInterval))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.refreshInterval, in: 1...30, step: 1)
                }
            }

            Section("Menu Bar") {
                Picker("Show in menu bar", selection: $settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var alertsTab: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
            } footer: {
                Text("TopManager posts a macOS notification when a threshold is first crossed.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Thresholds") {
                sliderRow(title: "High CPU", value: $settings.cpuAlertThreshold,
                          range: 50...100, unit: "%")
                sliderRow(title: "Disk almost full", value: $settings.diskAlertPercent,
                          range: 80...99, unit: "%")
                VStack(alignment: .leading) {
                    HStack {
                        Text("Low battery")
                        Spacer()
                        Text("\(settings.lowBatteryPercent)%").monospacedDigit().foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.lowBatteryPercent) },
                        set: { settings.lowBatteryPercent = Int($0) }
                    ), in: 5...50, step: 5)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f%@", value.wrappedValue, unit))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
