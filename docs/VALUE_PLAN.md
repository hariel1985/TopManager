# TopManager — 10× Value Plan

## Thesis
TopManager today is a polished, **read-only Activity Monitor clone**: it *shows* numbers.
Its value ceiling is "I can see what's using my Mac and kill a process."

To make it ~10× more valuable we move it from **viewer → system-intelligence & control
center**: it watches the system for you, remembers its history, explains problems, exposes
data Activity Monitor hides, and lets you act — including always-on from the menu bar.

All existing features are preserved (several are improved).

## Value rubric (capability scoring)
| Dimension | Before | After (target) |
|---|---|---|
| Per-process depth | CPU, mem, threads, state | + disk I/O rate, energy impact, args, open files, full path, tree |
| Time memory | 60 in-RAM points, lost on quit | persistent history, minutes → 24h, survives restart |
| Proactivity | none | threshold alerts + native notifications + health score + diagnosis |
| Energy / battery | **absent** | battery health (cycles/condition/capacity) + per-process energy |
| Always-on surface | bare "12%" | rich menu-bar HUD: CPU/RAM/net + top consumers + quick-kill |
| Customization | none (all hardcoded) | Settings: refresh rate, menu metric, thresholds, launch-at-login |

## Increments
0. **Test harness** — XCTest target, `@testable import`, 5-gate process. ✅
1. **Persistent history** — `MetricsStore` ring buffer on disk; 1m/5m/1h/24h charts.
2. **Deep per-process data** — disk I/O, energy impact, args, open files, path; surface the
   (currently unused) `ProcessDetailView` as a real inspector; new sortable columns.
3. **Battery + energy** — IOKit `PowerMonitor`; Energy/Battery UI; menu-bar battery.
4. **Alerts + health** — `AlertEngine`, `UserNotifications`, in-app inbox, 0–100 health score,
   "why is my Mac slow?" diagnosis.
5. **Settings + rich menu bar** — configurable refresh/metric/thresholds, launch-at-login
   (`SMAppService`), menu-bar HUD with top consumers + quick actions.
6. **Verification** — full test run, runtime smoke, ground-truth cross-checks, sign, commit.

## Non-negotiables
- Never break a shipped feature (regression Gate 5).
- No new entitlements / no root / no privileged helper — must run & sign as-is.
- Every increment passes all five gates in `docs/TESTING.md` before moving on.
