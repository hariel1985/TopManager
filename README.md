# TopManager

A native macOS system monitor application built with SwiftUI. TopManager provides real-time monitoring of system resources including processes, applications, CPU, memory, GPU, storage, and network.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-GPL--3.0-green)

## Features

### Processes Tab
- View all running processes with CPU, memory, and thread information
- Sort by any column (name, PID, CPU%, memory, threads, user, state)
- Process states: Running, Sleeping, Stopped, Zombie
- Context menu to terminate, force kill, suspend, or resume processes
- Search processes by name or PID

### Apps Tab
- View running user-facing applications
- Shows app icons, CPU/memory usage, and bundle identifiers
- Quick actions: Activate, Hide, Quit, Force Quit
- Copy bundle ID to clipboard

### Performance Tab
- Real-time CPU usage graphs (global and per-core)
- Memory usage visualization with donut chart
- Network throughput monitoring
- Support for Apple Silicon P-cores and E-cores

### Power & Storage Tab
- System status: macOS version, uptime, thermal state
- CPU and GPU core counts
- GPU memory/VRAM usage
- Storage volumes with usage bars
- Network interface statistics

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for building)

## Building

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/TopManager.git
   ```

2. Open `TopManager.xcodeproj` in Xcode

3. Build and run (⌘R)

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built with SwiftUI and native macOS APIs including:
- `libproc` for process information
- `IOKit` for GPU and hardware monitoring
- `Metal` for GPU detection
- `SystemConfiguration` for network monitoring
