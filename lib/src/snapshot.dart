import 'live_timer.dart';

/// Where a [LiveTimer] is at a given instant.
enum TimerPhase {
  /// Nothing to show: no timer, past [LiveTimer.maxDuration], or completed
  /// with [TimerCompletion.idle].
  idle,

  /// Before [LiveTimer.endsAt] (or with no end).
  running,

  /// Past [LiveTimer.endsAt].
  completed,
}

/// What the widget shows for a [LiveTimer] at one instant.
///
/// This is the reference implementation of the rules: the Android provider
/// (`LiveTimerEngine.kt`) and the iOS template (`LiveTimerWidget.swift`)
/// mirror it, and `test/snapshot_test.dart` pins it down.
class TimerSnapshot {
  const TimerSnapshot._({
    required this.phase,
    this.progress,
    this.stageIndex,
    this.clock = Duration.zero,
    this.ticking = false,
    this.countingDown = false,
    this.title = '',
    this.subtitle,
  });

  factory TimerSnapshot.resolve(LiveTimer timer, DateTime now) {
    const idle = TimerSnapshot._(phase: TimerPhase.idle);
    final elapsed = now.difference(timer.startedAt);
    final max = timer.maxDuration;
    if (max != null && elapsed >= max) return idle;

    final end = timer.endsAt;
    final completed = end != null && !now.isBefore(end);
    if (completed && timer.onComplete == TimerCompletion.idle) return idle;

    final goal = timer.goal;
    double? progress;
    if (goal != null) {
      progress = goal <= Duration.zero
          ? 1
          : (elapsed.inMilliseconds / goal.inMilliseconds).clamp(0, 1);
    }

    final stageIndex = _stageAt(timer, elapsed);
    final stage = stageIndex == null ? null : timer.stages[stageIndex];
    final percent = progress == null ? '' : '${(progress * 100).floor()}%';
    String fill(String text) => text.replaceAll('{percent}', percent);

    final title =
        (completed ? timer.completedTitle : null) ??
        stage?.title ??
        timer.title;
    final subtitle =
        (completed ? timer.completedSubtitle : null) ??
        stage?.subtitle ??
        timer.subtitle;

    final Duration clock;
    var ticking = true;
    var countingDown = false;
    if (!completed) {
      countingDown = timer.direction == TimerDirection.down;
      clock = countingDown ? end!.difference(now) : elapsed;
    } else if (timer.onComplete == TimerCompletion.freeze) {
      ticking = false;
      clock = timer.direction == TimerDirection.down ? Duration.zero : goal!;
    } else {
      // keepCounting: a countdown becomes overtime since the end.
      clock = timer.direction == TimerDirection.down
          ? now.difference(end)
          : elapsed;
    }

    return TimerSnapshot._(
      phase: completed ? TimerPhase.completed : TimerPhase.running,
      progress: progress,
      stageIndex: stageIndex,
      clock: clock.isNegative ? Duration.zero : clock,
      ticking: ticking,
      countingDown: countingDown,
      title: fill(title),
      subtitle: subtitle == null ? null : fill(subtitle),
    );
  }

  final TimerPhase phase;

  /// `0`–`1`; `null` without a goal.
  final double? progress;

  /// The reached [LiveTimer.stages] entry with the latest offset.
  final int? stageIndex;

  /// The value on the clock.
  final Duration clock;

  /// `false` once frozen by [TimerCompletion.freeze].
  final bool ticking;

  /// Whether [clock] goes down as time passes.
  final bool countingDown;

  /// Texts with their stage and completion overrides and `{percent}` filled.
  final String title;
  final String? subtitle;

  bool get isIdle => phase == TimerPhase.idle;

  /// The next instant after [now] at which [TimerSnapshot.resolve] gives a
  /// different phase or stage, or `null` if it never will. Widgets refresh
  /// there instead of polling.
  static DateTime? nextChange(LiveTimer timer, DateTime now) {
    final start = timer.startedAt;
    final candidates = [
      ?timer.endsAt,
      if (timer.maxDuration case final max?) start.add(max),
      for (final stage in timer.stages)
        if (stage.offsetIn(timer) case final offset?) start.add(offset),
    ].where((t) => t.isAfter(now)).toList()..sort();
    return candidates.firstOrNull;
  }

  static int? _stageAt(LiveTimer timer, Duration elapsed) {
    int? index;
    Duration? best;
    for (var i = 0; i < timer.stages.length; i++) {
      final offset = timer.stages[i].offsetIn(timer);
      if (offset == null || offset > elapsed) continue;
      // Later in the list wins a tie.
      if (best == null || offset >= best) {
        best = offset;
        index = i;
      }
    }
    return index;
  }
}
