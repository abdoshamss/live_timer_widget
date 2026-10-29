import 'dart:ui';

import 'snapshot.dart';
import 'widget_image.dart';

/// Which way the widget's clock runs.
enum TimerDirection {
  /// Elapsed time since [LiveTimer.startedAt]: `00:00`, `00:01`, …
  up,

  /// Time left until [LiveTimer.endsAt]: `…`, `00:01`, `00:00`.
  down,
}

/// What the widget does once [LiveTimer.endsAt] has passed.
enum TimerCompletion {
  /// Keep running. A count-up clock goes on counting; a countdown turns into
  /// an overtime clock counting up from the end.
  keepCounting,

  /// Stop the clock on its final value (the full duration counting up, `0:00`
  /// counting down).
  freeze,

  /// Go back to the idle content, as if [LiveTimerWidget.stop] was called.
  idle,
}

/// A timer shown live on the home-screen widget.
///
/// Only instants are stored — never a running number — so the clock, the
/// progress and the current [stages] keep moving with the app closed, and the
/// widget ends on its own at [endsAt] or [maxDuration].
///
/// Every text supports the `{percent}` placeholder, filled in by the widget
/// with the current progress (`42%`).
class LiveTimer {
  LiveTimer({
    required this.startedAt,
    DateTime? endsAt,
    Duration? goal,
    this.direction = TimerDirection.up,
    this.onComplete = TimerCompletion.keepCounting,
    this.maxDuration,
    this.title = '',
    this.subtitle,
    this.completedTitle,
    this.completedSubtitle,
    this.image,
    this.accent,
    this.stages = const [],
    this.showProgress = true,
    this.link,
  }) : endsAt = endsAt ?? (goal == null ? null : startedAt.add(goal)),
       assert(endsAt == null || goal == null, 'Pass endsAt or goal, not both'),
       assert(
         direction == TimerDirection.up || endsAt != null || goal != null,
         'A countdown needs endsAt or goal',
       ),
       assert(
         maxDuration == null || !maxDuration.isNegative,
         'maxDuration must not be negative',
       );

  /// When the timer started. May be in the past (a backdated session).
  final DateTime startedAt;

  /// The goal. Without it there is no progress, and [onComplete] never
  /// applies.
  final DateTime? endsAt;

  final TimerDirection direction;
  final TimerCompletion onComplete;

  /// A hard stop after [startedAt], whatever [endsAt] says — the widget goes
  /// back to idle by itself. Use it when the server ends sessions on its own
  /// and the push that says so might never arrive.
  final Duration? maxDuration;

  /// Shown above the clock, e.g. "Fasting · {percent}".
  final String title;

  /// Shown below the clock on medium and larger widgets, e.g. "Ends 8:30 PM".
  final String? subtitle;

  /// Replaces [title] once [endsAt] has passed.
  final String? completedTitle;

  /// Replaces [subtitle] once [endsAt] has passed.
  final String? completedSubtitle;

  /// The background photo. A reached [TimerStage.image] replaces it.
  final WidgetImage? image;

  /// Overrides [LiveTimerStyle.accent] for this timer.
  final Color? accent;

  /// Milestones that change the widget's content as time goes on.
  final List<TimerStage> stages;

  /// Whether the progress bar is shown. It never shows without [endsAt].
  final bool showProgress;

  /// Passed back in [LiveTimerTap.link] when the widget is tapped.
  final Uri? link;

  Duration? get goal => endsAt?.difference(startedAt);

  /// What the widget shows at [now]. The native widgets apply the same rules.
  TimerSnapshot snapshotAt(DateTime now) => TimerSnapshot.resolve(this, now);

  List<WidgetImage> get images => [?image, for (final s in stages) ?s.image];

  Map<String, Object?> toJson(String? Function(WidgetImage?) imageName) => {
    'startMs': startedAt.millisecondsSinceEpoch,
    'endMs': endsAt?.millisecondsSinceEpoch,
    'direction': direction.name,
    'completion': onComplete.name,
    'maxMs': maxDuration?.inMilliseconds,
    'title': title,
    'subtitle': subtitle,
    'completedTitle': completedTitle,
    'completedSubtitle': completedSubtitle,
    'image': imageName(image),
    'accent': accent?.toARGB32(),
    'showProgress': showProgress,
    'link': link?.toString(),
    'stages': [for (final s in stages) s.toJson(imageName)],
  };
}

/// A milestone of a [LiveTimer]. Once reached, its non-null fields replace
/// the timer's own until the next stage is reached.
///
/// ```dart
/// stages: [
///   TimerStage.after(Duration(hours: 12), title: 'Fat burning'),
///   TimerStage.atProgress(0.5, image: WidgetImage.asset('assets/half.png')),
/// ]
/// ```
class TimerStage {
  /// Reached [after] this long since [LiveTimer.startedAt].
  const TimerStage.after(
    Duration this.after, {
    this.title,
    this.subtitle,
    this.image,
    this.accent,
  }) : progress = null;

  /// Reached at this fraction (`0`–`1`) of [LiveTimer.goal]. Never reached
  /// (except `0`) by a timer without a goal.
  const TimerStage.atProgress(
    double this.progress, {
    this.title,
    this.subtitle,
    this.image,
    this.accent,
  }) : after = null,
       assert(progress >= 0 && progress <= 1, 'progress must be in 0–1');

  final Duration? after;
  final double? progress;
  final String? title;
  final String? subtitle;
  final WidgetImage? image;
  final Color? accent;

  /// How long after the start this stage is reached; `null` if never.
  Duration? offsetIn(LiveTimer timer) {
    if (after != null) return after;
    if (progress == 0) return Duration.zero;
    final goal = timer.goal;
    if (goal == null || goal <= Duration.zero) return null;
    return Duration(milliseconds: (goal.inMilliseconds * progress!).round());
  }

  Map<String, Object?> toJson(String? Function(WidgetImage?) imageName) => {
    'afterMs': after?.inMilliseconds,
    'progress': progress,
    'title': title,
    'subtitle': subtitle,
    'image': imageName(image),
    'accent': accent?.toARGB32(),
  };
}
