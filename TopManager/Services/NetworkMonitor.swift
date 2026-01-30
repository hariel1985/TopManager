import Foundation
import Darwin

final class NetworkMonitor {
    private var previousStats: [String: (download: UInt64, upload: UInt64, timestamp: Date)] = [:]

    func fetchNetworkInfo() -> NetworkInfo {
        let interfaces = fetchInterfaces()

        let totalDownload = interfaces.reduce(0.0) { $0 + $1.downloadRate }
        let totalUpload = interfaces.reduce(0.0) { $0 + $1.uploadRate }
        let totalDownloadBytes = interfaces.reduce(UInt64(0)) { $0 + $1.downloadBytes }
        let totalUploadBytes = interfaces.reduce(UInt64(0)) { $0 + $1.uploadBytes }

        return NetworkInfo(
            interfaces: interfaces,
            totalDownloadRate: totalDownload,
            totalUploadRate: totalUpload,
            totalDownloadBytes: totalDownloadBytes,
            totalUploadBytes: totalUploadBytes
        )
    }

    private func fetchInterfaces() -> [NetworkInterface] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }

        defer { freeifaddrs(ifaddr) }

        var interfaceStats: [String: (download: UInt64, upload: UInt64)] = [:]
        var currentAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let addr = currentAddr {
            let interface = addr.pointee

            if interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)

                if shouldIncludeInterface(name: name),
                   let data = interface.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee

                    let download = UInt64(networkData.ifi_ibytes)
                    let upload = UInt64(networkData.ifi_obytes)

                    if let existing = interfaceStats[name] {
                        interfaceStats[name] = (
                            download: existing.download + download,
                            upload: existing.upload + upload
                        )
                    } else {
                        interfaceStats[name] = (download: download, upload: upload)
                    }
                }
            }

            currentAddr = interface.ifa_next
        }

        let now = Date()
        var interfaces: [NetworkInterface] = []

        for (name, stats) in interfaceStats {
            var downloadRate: Double = 0
            var uploadRate: Double = 0

            if let previous = previousStats[name] {
                let timeDelta = now.timeIntervalSince(previous.timestamp)
                if timeDelta > 0 {
                    // Handle counter reset/overflow: only compute rate if current >= previous
                    if stats.download >= previous.download {
                        downloadRate = Double(stats.download - previous.download) / timeDelta
                    }
                    if stats.upload >= previous.upload {
                        uploadRate = Double(stats.upload - previous.upload) / timeDelta
                    }
                }
            }

            previousStats[name] = (stats.download, stats.upload, now)

            let isActive = downloadRate > 0 || uploadRate > 0 || stats.download > 0 || stats.upload > 0

            interfaces.append(NetworkInterface(
                name: name,
                displayName: displayName(for: name),
                downloadBytes: stats.download,
                uploadBytes: stats.upload,
                downloadRate: downloadRate,
                uploadRate: uploadRate,
                isActive: isActive
            ))
        }

        return interfaces.sorted { $0.name < $1.name }
    }

    private func shouldIncludeInterface(name: String) -> Bool {
        // Include common physical interfaces
        let includedPrefixes = ["en", "bridge", "awdl", "llw", "utun"]
        return includedPrefixes.contains { name.hasPrefix($0) }
    }

    private func displayName(for interface: String) -> String {
        if interface.hasPrefix("en") {
            if interface == "en0" {
                return "Wi-Fi / Ethernet"
            }
            return "Ethernet \(interface)"
        } else if interface.hasPrefix("bridge") {
            return "Bridge"
        } else if interface.hasPrefix("awdl") {
            return "AirDrop"
        } else if interface.hasPrefix("llw") {
            return "Low Latency WLAN"
        } else if interface.hasPrefix("utun") {
            return "VPN Tunnel"
        }
        return interface
    }
}
