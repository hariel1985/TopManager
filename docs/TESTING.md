# TopManager — Testing Process

This document defines the repeatable test process used while evolving TopManager.
Every feature increment must pass all five gates below before it is considered done.

## Gate 1 — Compile
```bash
scripts/test.sh build
```
Fast feedback that the code compiles for `platform=macOS,arch=arm64`. First gate on every change.

## Gate 2 — Unit tests (automated, self-run)
```bash
scripts/test.sh test        # or: xcodebuild ... test
```
Pure-logic is covered by XCTest in `TopManagerTests/` using `@testable import TopManager`.
The suite intentionally targets deterministic logic (no live system state):

- **Formatting / model math** — bytes, rates, percentages, uptime, usage %.
- **MetricsStore** — ring-buffer trim, persistence round-trip, downsampling per range.
- **Energy heuristic** — score is monotonic in CPU and wakeups, clamped to 0–100.
- **Alert engine** — threshold crossings fire/clear correctly, sustained-window logic,
  de-duplication (no alert storms), severity ordering.
- **Health score** — 0–100, decreases with pressure/thermal/swap/disk load.
- **Battery math** — time-remaining and capacity-health formatting.

Tests must stay hermetic: no sleeping on real timers, no asserting on live CPU numbers.

## Gate 3 — Runtime smoke test (self-run on this machine)
Launch the built app, drive real load, confirm no crash and data populates.
```bash
# build a runnable .app
xcodebuild -project TopManager.xcodeproj -scheme TopManager -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
APP=$(find ~/Library/Developer/Xcode/DerivedData/TopManager-*/Build/Products/Debug -name TopManager.app | head -1)
open "$APP"
# generate CPU load in the background, then verify TopManager surfaces it
yes > /dev/null & LOAD=$!; sleep 8; kill $LOAD
```
Verify: process list shows the load generator near the top, charts move, no crash in
`Console`/stderr, menu bar updates, alerts fire when thresholds are crossed.

## Gate 4 — Ground-truth cross-checks
TopManager's numbers are validated against OS tools so we don't ship wrong data:

| TopManager metric      | Ground truth command                        |
|------------------------|---------------------------------------------|
| Per-process CPU/mem    | `ps -Ao pid,pcpu,pmem,comm -r | head`       |
| System memory          | `vm_stat`, `sysctl vm.swapusage`            |
| Disk volumes / free    | `df -h`                                      |
| Battery / power        | `pmset -g batt`, `ioreg -rn AppleSmartBattery` |
| Thermal state          | `pmset -g therm`                             |
| Network throughput     | `netstat -ib`                                |

Small deltas are expected (sampling windows differ); order-of-magnitude or ranking
mismatches are bugs.

## Gate 5 — Regression: original features intact
Manually confirm each shipped feature still works: Processes (sort/search/kill/suspend/
resume), Apps (activate/hide/quit/force-quit/copy bundle id), Performance (CPU/Mem/Net
charts), Power & Storage (system/GPU/storage/network), and the menu-bar readout.

## Loop
```
implement slice → Gate 1 → Gate 2 → Gate 3 → Gate 4 → Gate 5 → checkpoint commit
```
Repeat per increment until the value rubric in `docs/VALUE_PLAN.md` is met.
