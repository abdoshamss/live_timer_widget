# live_timer_widget

Live timers on the home screen, driven from Dart.

An **Android app widget** and an **iOS WidgetKit widget** (home screen and lock screen) that tick every second with the app closed. Count up or down, show progress toward a goal, switch title, image and color at milestones, and stop on their own. You write no Kotlin or Swift.

```dart
await LiveTimerWidget.start(LiveTimer(
  startedAt: DateTime.now(),
  goal: const Duration(hours: 16),
  title: 'Fasting',
  completedTitle: 'Goal reached',
));
```

Use it for fasting, workouts, focus sessions, cooking, parking meters, delivery ETAs: anything with a start, and maybe an end.

## Features

- **Ticks with the app closed.** The widget stores instants, never a running number. The clock is native (`Chronometer` on Android, `Text(.timer)` on iOS), so it's always to the second and uses no battery between redraws.
- **Count up or down**, with an optional goal, a progress bar and a `{percent}` placeholder in any text.
- **Completion behavior.** At the goal the timer can keep counting (a countdown turns into overtime), freeze on its final value, or go back to idle.
- **Hard stop.** `maxDuration` ends the timer by itself, even if the push that should have stopped it never arrives.
- **Stages.** Milestones by elapsed time or by progress replace the title, subtitle, background photo and accent color while the app stays closed.
- **Idle state** with its own title, subtitle and action button.
- **Images** from assets, files, the network, memory or any `ImageProvider`. They are downscaled, stored once, and cleaned up when no longer used.
- **Styling.** Colors, an optional gradient, and a photo scrim that keeps text readable. `LiveTimerStyle.fromColorScheme` matches your app's theme.
- **RTL and LTR.** The direction follows the app's language, not the device's.
- **Taps.** Deep links back into the app, with the widget body and the action button told apart. Works on a cold start too.
- **Pin from the app.** On Android 8+, `requestPin()` shows the system "add widget" prompt.
- **Lock screen widgets** on iOS 16+: rectangular, circular gauge and inline.
- **Safe from background isolates.** Call it from a push handler to keep the widget in sync while the app is closed.
- **One-command iOS setup.** It adds the extension target, App Group and entitlements to your Xcode project.

## Install

```yaml
dependencies:
  live_timer_widget: ^0.1.0
```

Requirements: Flutter 3.38+, Android 7.0+ (API 24), iOS 15+ (iOS 16+ for the lock screen widgets).

### Android

Nothing to do. The widget is declared in the plugin's manifest, so it shows up in the launcher's widget picker as soon as you depend on the package.

### iOS

A WidgetKit widget has to be an extension target inside your Xcode project, and no package can add one by itself. This command does it for you. Run it from your app's root:

```sh
dart run live_timer_widget:setup_ios --app-group group.com.example.myapp
```

It:

1. copies the widget into `ios/LiveTimerWidget/`: one SwiftUI file that you're free to restyle,
2. adds a `LiveTimerWidget` extension target and embeds it in `Runner`,
3. gives both targets the App Group, which is how the app and the widget share data.

Then open `ios/Runner.xcworkspace` once. Under **Signing & Capabilities**, check that both `Runner` and `LiveTimerWidget` use the same team and have the App Group ticked. Build, and you're done.

It's safe to run again. Files you've edited are kept unless you pass `--force`. Other options are `--display-name`, `--description`, `--target`, `--kind` and `--deployment-target`. See `--help`.

> It uses the `xcodeproj` Ruby gem, which CocoaPods already installs. If it's missing, run `gem install xcodeproj`.

## Usage

### 1. Initialize

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiveTimerWidget.initialize(iOSAppGroupId: 'group.com.example.myapp');
  runApp(const MyApp());
}
```

### 2. Configure the look and the idle state

```dart
await LiveTimerWidget.configure(
  style: LiveTimerStyle.fromColorScheme(Theme.of(context).colorScheme),
  idle: LiveTimerIdle(
    title: 'Ready to fast?',
    subtitle: 'Your timer shows up here',
    actionLabel: 'Start',
    actionLink: Uri.parse('myapp://start'),
  ),
  textDirection: Directionality.of(context),
);
```

Each argument is optional and replaces only its own part. Call it again whenever the language changes, because the widget can't translate on its own: every text is written already localized.

### 3. Start and stop

```dart
await LiveTimerWidget.start(LiveTimer(
  startedAt: session.startedAt,          // may be in the past
  goal: const Duration(hours: 16),       // or endsAt: …
  maxDuration: const Duration(hours: 72),
  title: 'Fasting',
  subtitle: 'Ends at 8:30 PM',           // format it in your locale
  completedTitle: 'Goal reached 🎉',
  image: const WidgetImage.asset('assets/widget/start.png'),
  link: Uri.parse('myapp://session/${session.id}'),
  stages: [
    TimerStage.after(const Duration(hours: 12),
        title: 'Fat burning · {percent}',
        image: WidgetImage.network(stage.imageUrl)),
    const TimerStage.atProgress(1, accent: Colors.amber),
  ],
));

await LiveTimerWidget.stop();   // back to idle, keeps style + idle
await LiveTimerWidget.reset();  // wipe everything (e.g. on logout)
```

| `LiveTimer` option | Meaning |
|---|---|
| `direction` | `TimerDirection.up` (elapsed) or `.down` (time left, needs a goal) |
| `onComplete` | at the goal: `keepCounting` (default), `freeze`, or `idle` |
| `maxDuration` | hard stop after the start, back to idle |
| `showProgress` | show the progress bar (only when there's a goal) |
| `accent` | overrides the style's accent for this timer |

When several stages are reached, the one reached last wins, and its non-null fields replace the timer's own.

The rules are documented and tested in Dart. `timer.snapshotAt(now)` tells you exactly what the widget shows at any instant, which is handy for showing the same state inside your app.

### 4. Handle taps

```dart
final launch = await LiveTimerWidget.initialTap;   // the app was opened by the widget
LiveTimerWidget.taps.listen((tap) {                // the app was already running
  if (tap.link != null) router.go(tap.link!.path);
});
```

`tap.target` tells the widget body (`widget`) apart from the idle button (`action`). Taps don't go through Flutter's own deep linking, so they never push a route behind your back.

### Keeping it in sync from a push

Calls work from a background isolate, so a silent push can update the widget while the app is closed:

```dart
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  if (message.data['type'] != 'session_updated') return;
  await LiveTimerWidget.initialize(iOSAppGroupId: 'group.com.example.myapp');
  if (message.data['status'] == 'active') {
    await LiveTimerWidget.start(LiveTimer(
      startedAt: DateTime.parse(message.data['started_at']),
      title: 'Fasting',
    ));
  } else {
    await LiveTimerWidget.stop();
  }
}
```

Every call reads the stored state back first, so the app and a push handler never overwrite each other's changes.

### Asking the user to add the widget

```dart
if (await LiveTimerWidget.isPinSupported) {
  await LiveTimerWidget.requestPin();  // Android 8+; iOS has no such API
}
final placed = await LiveTimerWidget.installedCount;
```

## Customizing

**iOS:** `ios/LiveTimerWidget/LiveTimerWidget.swift` is yours. Change the views, fonts or families. Keep the data model and `Snapshot.resolve` as they are, since they mirror the Dart rules.

**Android:** any `ltw_*` resource can be overridden by defining one with the same name in your app:

| Resource | What |
|---|---|
| `@string/ltw_widget_label` | name in the widget picker |
| `@string/ltw_widget_description` | description in the picker |
| `@string/ltw_idle_title`, `@string/ltw_idle_subtitle` | texts before the first `configure` |
| `@color/ltw_background` | color before the first draw |
| `@dimen/ltw_padding` | inner padding |
| `@layout/ltw_widget` | the whole layout: keep every `ltw_*` id |

The strings ship in English and Arabic.

Don't want the widget on Android? Remove it in your app's manifest:

```xml
<receiver
    android:name="io.github.abdoshamss.live_timer_widget.LiveTimerWidgetProvider"
    tools:node="remove" />
```

## How it works

```
 Dart ── start / configure ──▶ JSON + PNGs in shared storage ──▶ native widget
                               (SharedPreferences / App Group)    │
                                                                  ├─ clock: ticks natively, every second
                                                                  └─ progress, stage, completion:
                                                                     redrawn when they change
```

- **Android:** a non-wakeup alarm redraws at the next stage, the goal or the hard stop, and about every half percent of progress in between. Non-wakeup alarms only fire while the screen is on, so a running timer costs nothing with the screen off. Time-zone, clock and locale changes trigger a redraw too.
- **iOS:** a timeline of entries is computed at each of those instants, so WidgetKit swaps them in on time without waking the app.

## Limits

- On iOS, widgets refresh on WidgetKit's budget. The clock is always exact, but a change you push may take a moment to show.
- One timer per app. Every placed copy of the widget shows the same timer.
- The clock reads `MM:SS` under an hour and `H:MM:SS` above it, the format of the platforms' native timers.

## License

MIT
