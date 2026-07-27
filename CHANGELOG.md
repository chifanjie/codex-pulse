# Changelog

## Unreleased

- Removed the legacy floating detail panel and its deep-link entry point.
- Kept the native WidgetKit widgets and menu bar data service.
- Decoupled five-second local refreshes from slower account requests.
- Reduced the host-side WidgetKit reload delay from 60 seconds to 15 seconds.
- Fixed active-task totals when more than six tasks are running.
- Reworked local Token metrics to use deduplicated daily and current-turn
  deltas, excluding inherited subagent history.
- Preserved successful account data when only one App Server request fails,
  with short retries and bounded backoff.
- Added the account Token Activity cutoff date so delayed upstream statistics
  are not presented as real time.

## 2.0.0 — 2026-07-27

- Added a native macOS WidgetKit extension.
- Added Overview, Quota, Token, and Tasks widgets.
- Added system small, medium, and large families.
- Added a read-only snapshot bridge between the menu bar host and sandboxed extension.
- Added native macOS typography, SF Symbols, semantic colors, and system-managed placement.
- Added privacy-sensitive task titles.
- Added low-frequency snapshot heartbeats to prevent false stale-data warnings.
- Added an original project-owned app icon.
- Made launch at login explicitly opt-in for public builds.
- Redacted personal metrics and task identifiers from diagnostic probe output.
- Kept the original detail panel as an optional companion view.
