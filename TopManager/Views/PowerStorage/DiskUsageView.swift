import SwiftUI

struct DiskUsageView: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: volumeIcon)
                    .foregroundColor(.secondary)

                Text(volume.name)
                    .fontWeight(.medium)

                Spacer()

                Text(volume.mountPoint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: volume.usagePercentage, total: 100)
                .tint(usageColor)

            HStack {
                Text("\(formatBytes(volume.usedSpace)) used")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(formatBytes(volume.freeSpace)) free")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(formatBytes(volume.totalSpace)) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
        }
    }

    private var volumeIcon: String {
        if volume.isRemovable {
            return "externaldrive"
        } else if volume.mountPoint == "/" {
            return "internaldrive.fill"
        } else {
            return "internaldrive"
        }
    }

    private var usageColor: Color {
        if volume.usagePercentage > 90 {
            return .red
        } else if volume.usagePercentage > 75 {
            return .orange
        } else {
            return .blue
        }
    }
}

#Preview {
    VStack {
        DiskUsageView(volume: VolumeInfo(
            name: "Macintosh HD",
            mountPoint: "/",
            totalSpace: 500 * 1024 * 1024 * 1024,
            freeSpace: 150 * 1024 * 1024 * 1024,
            fileSystem: "apfs",
            isRemovable: false,
            isInternal: true
        ))

        DiskUsageView(volume: VolumeInfo(
            name: "External Drive",
            mountPoint: "/Volumes/External",
            totalSpace: 1024 * 1024 * 1024 * 1024,
            freeSpace: 800 * 1024 * 1024 * 1024,
            fileSystem: "apfs",
            isRemovable: true,
            isInternal: false
        ))
    }
    .padding()
}
