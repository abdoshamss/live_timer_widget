import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_timer_widget/live_timer_widget.dart';

// These rules are mirrored natively (LiveTimerEngine.kt and the iOS
// template's Snapshot): a change here must be made there too.
void main() {
  final start = DateTime(2026, 1, 1, 8);
  DateTime at(Duration d) => start.add(d);

  group('count up', () {
    final timer = LiveTimer(
      startedAt: start,
      goal: const Duration(hours: 16),
      title: 'Fasting · {percent}',
      subtitle: 'until 00:00',
      completedTitle: 'Done',
    );

    test('runs with progress and fills {percent}', () {
      final s = timer.snapshotAt(at(const Duration(hours: 4)));
      expect(s.phase, TimerPhase.running);
      expect(s.progress, 0.25);
      expect(s.clock, const Duration(hours: 4));
      expect(s.ticking, isTrue);
      expect(s.countingDown, isFalse);
      expect(s.title, 'Fasting · 25%');
      expect(s.subtitle, 'until 00:00');
    });

    test('rounds the percentage down', () {
      final s = timer.snapshotAt(at(const Duration(hours: 15, minutes: 59)));
      expect(s.title, 'Fasting · 99%');
    });

    test('keeps counting past the goal by default', () {
      final s = timer.snapshotAt(at(const Duration(hours: 20)));
      expect(s.phase, TimerPhase.completed);
      expect(s.progress, 1);
      expect(s.clock, const Duration(hours: 20));
      expect(s.ticking, isTrue);
      expect(s.title, 'Done');
    });

    test('a start in the future shows zero', () {
      final s = timer.snapshotAt(start.subtract(const Duration(minutes: 5)));
      expect(s.phase, TimerPhase.running);
      expect(s.progress, 0);
      expect(s.clock, Duration.zero);
    });
  });

  group('count down', () {
    LiveTimer countdown(TimerCompletion onComplete) => LiveTimer(
      startedAt: start,
      goal: const Duration(minutes: 10),
      direction: TimerDirection.down,
      onComplete: onComplete,
    );

    test('shows time left', () {
      final s = countdown(
        TimerCompletion.keepCounting,
      ).snapshotAt(at(const Duration(minutes: 3)));
      expect(s.clock, const Duration(minutes: 7));
      expect(s.countingDown, isTrue);
    });

    test('keepCounting turns into overtime', () {
      final s = countdown(
        TimerCompletion.keepCounting,
      ).snapshotAt(at(const Duration(minutes: 12)));
      expect(s.phase, TimerPhase.completed);
      expect(s.clock, const Duration(minutes: 2));
      expect(s.countingDown, isFalse);
      expect(s.ticking, isTrue);
    });

    test('freeze stops on zero', () {
      final s = countdown(
        TimerCompletion.freeze,
      ).snapshotAt(at(const Duration(minutes: 12)));
      expect(s.clock, Duration.zero);
      expect(s.ticking, isFalse);
    });

    test('idle goes back to idle at the end', () {
      final timer = countdown(TimerCompletion.idle);
      expect(timer.snapshotAt(at(const Duration(minutes: 10))).isIdle, isTrue);
      expect(timer.snapshotAt(at(const Duration(minutes: 9))).isIdle, isFalse);
    });

    test('needs a goal', () {
      expect(
        () => LiveTimer(startedAt: start, direction: TimerDirection.down),
        throwsAssertionError,
      );
    });
  });

  test('freeze counting up stops on the goal', () {
    final s = LiveTimer(
      startedAt: start,
      goal: const Duration(hours: 1),
      onComplete: TimerCompletion.freeze,
    ).snapshotAt(at(const Duration(hours: 3)));
    expect(s.clock, const Duration(hours: 1));
    expect(s.ticking, isFalse);
  });

  test('maxDuration ends the timer whatever the goal', () {
    final timer = LiveTimer(
      startedAt: start,
      maxDuration: const Duration(hours: 72),
    );
    expect(timer.snapshotAt(at(const Duration(hours: 71))).isIdle, isFalse);
    expect(timer.snapshotAt(at(const Duration(hours: 72))).isIdle, isTrue);
  });

  test('no goal: no progress, never completes', () {
    final s = LiveTimer(
      startedAt: start,
      title: '{percent}',
    ).snapshotAt(at(const Duration(days: 3)));
    expect(s.phase, TimerPhase.running);
    expect(s.progress, isNull);
    expect(s.title, '');
  });

  group('stages', () {
    final timer = LiveTimer(
      startedAt: start,
      goal: const Duration(hours: 10),
      title: 'Base',
      subtitle: 'Base sub',
      completedTitle: 'Done',
      stages: const [
        TimerStage.atProgress(0.5, title: 'Half', accent: Color(0xFFFF0000)),
        TimerStage.after(Duration(hours: 2), title: 'Two hours'),
        TimerStage.after(Duration(hours: 5), subtitle: 'Five, by time'),
      ],
    );

    test('none reached yet', () {
      final s = timer.snapshotAt(at(const Duration(hours: 1)));
      expect(s.stageIndex, isNull);
      expect(s.title, 'Base');
    });

    test('the reached stage with the latest offset wins, in any order', () {
      expect(timer.snapshotAt(at(const Duration(hours: 3))).stageIndex, 1);
      expect(timer.snapshotAt(at(const Duration(hours: 3))).title, 'Two hours');
    });

    test('a tie goes to the later stage; null fields fall back', () {
      final s = timer.snapshotAt(at(const Duration(hours: 5)));
      // 50% of 10h and "after 5h" are both at 5h.
      expect(s.stageIndex, 2);
      expect(s.title, 'Base');
      expect(s.subtitle, 'Five, by time');
    });

    test('completion overrides a stage title', () {
      expect(timer.snapshotAt(at(const Duration(hours: 11))).title, 'Done');
    });

    test('a progress stage is never reached without a goal', () {
      final noGoal = LiveTimer(
        startedAt: start,
        stages: const [
          TimerStage.atProgress(0, title: 'Start'),
          TimerStage.atProgress(0.5, title: 'Never'),
        ],
      );
      expect(noGoal.snapshotAt(at(const Duration(days: 1))).title, 'Start');
    });
  });

  test('nextChange lists stages, the end and the hard stop', () {
    final timer = LiveTimer(
      startedAt: start,
      goal: const Duration(hours: 10),
      maxDuration: const Duration(hours: 24),
      stages: const [
        TimerStage.after(Duration(hours: 2)),
        TimerStage.atProgress(0.5),
      ],
    );
    DateTime? next(Duration d) => TimerSnapshot.nextChange(timer, at(d));
    expect(next(Duration.zero), at(const Duration(hours: 2)));
    expect(next(const Duration(hours: 2)), at(const Duration(hours: 5)));
    expect(next(const Duration(hours: 6)), at(const Duration(hours: 10)));
    expect(next(const Duration(hours: 12)), at(const Duration(hours: 24)));
    expect(next(const Duration(hours: 25)), isNull);
  });
}
