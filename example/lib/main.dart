import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_timer_widget/live_timer_widget.dart';

/// Must match the App Group `dart run live_timer_widget:setup_ios` was given.
const appGroupId = 'group.io.github.abdoshamss.liveTimerWidgetExample';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiveTimerWidget.initialize(iOSAppGroupId: appGroupId);
  await LiveTimerWidget.configure(
    style: const LiveTimerStyle(
      background: Color(0xFF2A1B45),
      backgroundEnd: Color(0xFF6B4C9F),
      accent: Color(0xFF8AC443),
    ),
    idle: LiveTimerIdle(
      title: 'Ready when you are',
      subtitle: 'Start a timer and it keeps running here',
      actionLabel: 'Start',
      link: Uri.parse('example://home'),
      actionLink: Uri.parse('example://start'),
    ),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'live_timer_widget',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6B4C9F)),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _log = <String>[];
  StreamSubscription<LiveTimerTap>? _taps;
  int _installed = 0;
  bool _canPin = false;
  bool _rtl = false;

  @override
  void initState() {
    super.initState();
    LiveTimerWidget.initialTap.then((tap) {
      if (tap != null) _record('launched by $tap');
    });
    _taps = LiveTimerWidget.taps.listen((tap) => _record('tapped $tap'));
    _refreshInfo();
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  Future<void> _refreshInfo() async {
    final installed = await LiveTimerWidget.installedCount;
    final canPin = await LiveTimerWidget.isPinSupported;
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _canPin = canPin;
    });
  }

  void _record(String line) {
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    await action();
    _record(label);
    await _refreshInfo();
  }

  /// A backdated fast with milestones that change the title as it goes.
  Future<void> _startFast() {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    const goal = Duration(hours: 16);
    return _run(
      'started a 16h fast, 2h in',
      () => LiveTimerWidget.start(
        LiveTimer(
          startedAt: start,
          goal: goal,
          maxDuration: const Duration(hours: 72),
          title: 'Fasting',
          subtitle: 'Goal at ${_clock(start.add(goal))}',
          completedTitle: 'Goal reached',
          link: Uri.parse('example://fast'),
          stages: const [
            TimerStage.after(
              Duration(hours: 4),
              title: 'Sugar dropping · {percent}',
            ),
            TimerStage.after(
              Duration(hours: 12),
              title: 'Fat burning · {percent}',
            ),
            TimerStage.atProgress(1, accent: Color(0xFFFFC857)),
          ],
        ),
      ),
    );
  }

  /// A short countdown that goes back to idle on its own.
  Future<void> _startCountdown() => _run(
    'started a 2 min countdown',
    () => LiveTimerWidget.start(
      LiveTimer(
        startedAt: DateTime.now(),
        goal: const Duration(minutes: 2),
        direction: TimerDirection.down,
        onComplete: TimerCompletion.idle,
        title: 'Tea is brewing',
        subtitle: 'Back to idle when done',
        link: Uri.parse('example://tea'),
      ),
    ),
  );

  /// No goal: a plain stopwatch without a progress bar.
  Future<void> _startStopwatch() => _run(
    'started a stopwatch',
    () => LiveTimerWidget.start(
      LiveTimer(
        startedAt: DateTime.now(),
        title: 'Workout',
        subtitle: 'Tap to open the session',
        link: Uri.parse('example://workout'),
      ),
    ),
  );

  Future<void> _toggleDirection() {
    _rtl = !_rtl;
    return _run(
      _rtl ? 'right to left' : 'left to right',
      () => LiveTimerWidget.configure(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      ),
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('live_timer_widget')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Widgets placed: $_installed'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _startFast,
                child: const Text('16h fast'),
              ),
              FilledButton(
                onPressed: _startCountdown,
                child: const Text('2 min countdown'),
              ),
              FilledButton(
                onPressed: _startStopwatch,
                child: const Text('Stopwatch'),
              ),
              OutlinedButton(
                onPressed: () => _run('stopped', LiveTimerWidget.stop),
                child: const Text('Stop'),
              ),
              OutlinedButton(
                onPressed: () => _run('reset', LiveTimerWidget.reset),
                child: const Text('Reset'),
              ),
              OutlinedButton(
                onPressed: _toggleDirection,
                child: Text(_rtl ? 'LTR' : 'RTL'),
              ),
              if (_canPin)
                OutlinedButton(
                  onPressed: () =>
                      _run('asked to pin', LiveTimerWidget.requestPin),
                  child: const Text('Add to home screen'),
                ),
            ],
          ),
          const Divider(height: 32),
          for (final line in _log) Text(line),
        ],
      ),
    );
  }
}
