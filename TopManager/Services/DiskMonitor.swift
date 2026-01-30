import Foundation

final class DiskMonitor {
    func fetchDiskInfo() -> DiskInfo {
        let volumes = fetchVolumes()
        return DiskInfo(volumes: volumes)
    }

    private func fetchVolumes() -> [VolumeInfo] {
        var volumes: [VolumeInfo] = []

        let fileManager = FileManager.default
        guard let mountedVolumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey,
                .volumeIsInternalKey,
                .volumeLocalizedFormatDescriptionKey
            ],
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        for volumeURL in mountedVolumeURLs {
            do {
                let resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey,
                    .volumeIsRemovableKey,
                    .volumeIsInternalKey,
                    .volumeLocalizedFormatDescriptionKey
                ])

                let name = resourceValues.volumeName ?? volumeURL.lastPathComponent
                let totalSpace = UInt64(resourceValues.volumeTotalCapacity ?? 0)
                let freeSpace = UInt64(resourceValues.volumeAvailableCapacity ?? 0)
                let isRemovable = resourceValues.volumeIsRemovable ?? false
                let isInternal = resourceValues.volumeIsInternal ?? true
                let fileSystem = resourceValues.volumeLocalizedFormatDescription ?? "Unknown"

                let mountPoint = volumeURL.path

                // Skip system volumes
                guard shouldIncludeVolume(mountPoint: mountPoint) else {
                    continue
                }

                volumes.append(VolumeInfo(
                    name: name,
                    mountPoint: mountPoint,
                    totalSpace: totalSpace,
                    freeSpace: freeSpace,
                    fileSystem: fileSystem,
                    isRemovable: isRemovable,
                    isInternal: isInternal
                ))
            } catch {
                continue
            }
        }

        return volumes.sorted { $0.mountPoint < $1.mountPoint }
    }

    private func shouldIncludeVolume(mountPoint: String) -> Bool {
        let excludedPaths = [
            "/System/Volumes/VM",
            "/System/Volumes/Preboot",
            "/System/Volumes/Update",
            "/System/Volumes/xarts",
            "/System/Volumes/iSCPreboot",
            "/System/Volumes/Hardware"
        ]
        return !excludedPaths.contains(where: { mountPoint.hasPrefix($0) })
    }
}
