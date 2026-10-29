## 0.1.0

- Android app widget and iOS WidgetKit home and lock screen widget that tick every second with the app closed.
- Count up or down, goal and progress, `{percent}` placeholder, `keepCounting` / `freeze` / `idle` on completion, `maxDuration` hard stop.
- Stages by elapsed time or progress that swap title, subtitle, image and accent.
- Idle state with an action button; taps with deep links (`initialTap`, `taps`).
- Images from assets, files, network, memory or any `ImageProvider`, downscaled, stored once and pruned.
- `LiveTimerStyle` (with `fromColorScheme`), RTL / LTR.
- `requestPin` and `installedCount`.
- `dart run live_timer_widget:setup_ios` adds the extension target, App Group and entitlements.
