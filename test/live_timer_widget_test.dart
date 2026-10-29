import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_timer_widget/live_timer_widget.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePlatform extends LiveTimerWidgetPlatform
    with MockPlatformInterfaceMixin {
  String? stored;
  final images = <String, Uint8List>{};
  int saves = 0;

  Map<String, Object?> get state => jsonDecode(stored!) as Map<String, Object?>;

  @override
  Future<void> initialize({
    String? appGroupId,
    required String widgetKind,
  }) async {}

  @override
  Future<String?> load() async => stored;

  @override
  Future<void> save(String state) async {
    stored = state;
    saves++;
  }

  @override
  Future<bool> hasImage(String name) async => images.containsKey(name);

  @override
  Future<void> saveImage(String name, Uint8List png) async =>
      images[name] = png;

  @override
  Future<void> pruneImages(List<String> keep) async =>
      images.removeWhere((name, _) => !keep.contains(name));

  @override
  Future<int> installedCount() async => 1;

  @override
  Future<bool> isPinSupported() async => false;

  @override
  Future<bool> requestPin() async => false;

  @override
  Future<Map<Object?, Object?>?> initialTap() async => {
    'link': 'app://fast',
    'target': 'action',
  };

  @override
  Stream<Map<Object?, Object?>> taps() =>
      Stream.value({'link': null, 'target': 'widget'});
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlatform platform;

  setUp(() {
    platform = FakePlatform();
    LiveTimerWidgetPlatform.instance = platform;
    LiveTimerWidget.debugReset();
  });

  test('start writes the timer; configure keeps it', () async {
    final start = DateTime.fromMillisecondsSinceEpoch(1000000);
    await LiveTimerWidget.start(
      LiveTimer(
        startedAt: start,
        goal: const Duration(hours: 1),
        direction: TimerDirection.down,
        onComplete: TimerCompletion.freeze,
        title: 'T',
        link: Uri.parse('app://x'),
        stages: const [TimerStage.after(Duration(minutes: 5), title: 'S')],
      ),
    );
    await LiveTimerWidget.configure(
      style: const LiveTimerStyle(accent: Color(0xFF00FF00)),
      idle: const LiveTimerIdle(title: 'Idle', actionLabel: 'Go'),
      textDirection: TextDirection.rtl,
    );

    final state = platform.state;
    final timer = state['timer'] as Map;
    expect(timer['startMs'], 1000000);
    expect(timer['endMs'], 1000000 + 3600000);
    expect(timer['direction'], 'down');
    expect(timer['completion'], 'freeze');
    expect(timer['link'], 'app://x');
    expect((timer['stages'] as List).single, containsPair('afterMs', 300000));
    expect((state['style'] as Map)['accent'], 0xFF00FF00);
    expect((state['idle'] as Map)['actionLabel'], 'Go');
    expect(state['rtl'], isTrue);
    expect(state['version'], 1);
  });

  test('stop clears only the timer; reset clears everything', () async {
    await LiveTimerWidget.configure(idle: const LiveTimerIdle(title: 'Idle'));
    await LiveTimerWidget.start(LiveTimer(startedAt: DateTime.now()));
    expect(await LiveTimerWidget.isRunning, isTrue);

    await LiveTimerWidget.stop();
    expect(platform.state['timer'], isNull);
    expect((platform.state['idle'] as Map)['title'], 'Idle');
    expect(await LiveTimerWidget.isRunning, isFalse);

    await LiveTimerWidget.reset();
    expect(platform.state.containsKey('idle'), isFalse);
  });

  test('reads back state another isolate wrote', () async {
    await LiveTimerWidget.configure(idle: const LiveTimerIdle(title: 'Mine'));
    // A push handler in another isolate starts a timer.
    final other = Map<String, Object?>.of(platform.state)
      ..['timer'] = {'startMs': 5, 'completion': 'keepCounting'};
    platform.stored = jsonEncode(other);

    await LiveTimerWidget.configure(textDirection: TextDirection.ltr);
    expect((platform.state['timer'] as Map)['startMs'], 5);
  });

  test('images are downscaled, stored once and pruned', () async {
    final bytes = await _png(2000, 1000);
    final image = WidgetImage.memory(bytes, maxSize: 400);

    await LiveTimerWidget.start(
      LiveTimer(startedAt: DateTime.now(), image: image),
    );
    final name = (platform.state['timer'] as Map)['image'] as String;
    expect(platform.images.keys, [name]);

    final codec = await ui.instantiateImageCodec(platform.images[name]!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 400);
    expect(frame.image.height, 200);

    // Same bytes: not encoded again.
    platform.images[name] = Uint8List(0);
    await LiveTimerWidget.start(
      LiveTimer(startedAt: DateTime.now(), image: image),
    );
    expect(platform.images[name], isEmpty);

    await LiveTimerWidget.stop();
    expect(platform.images, isEmpty);
  });

  test('a failing image does not keep the timer off', () async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await LiveTimerWidget.start(
      LiveTimer(
        startedAt: DateTime.now(),
        title: 'Still here',
        image: WidgetImage.memory(Uint8List.fromList([1, 2, 3])),
      ),
    );
    expect((platform.state['timer'] as Map)['title'], 'Still here');
    expect((platform.state['timer'] as Map)['image'], isNull);
    expect(errors, hasLength(1));
  });

  test('calls apply in order', () async {
    final a = LiveTimerWidget.start(
      LiveTimer(startedAt: DateTime.now(), title: 'a'),
    );
    final b = LiveTimerWidget.stop();
    final c = LiveTimerWidget.start(
      LiveTimer(startedAt: DateTime.now(), title: 'c'),
    );
    await Future.wait([a, b, c]);
    expect((platform.state['timer'] as Map)['title'], 'c');
    expect(platform.saves, 3);
  });

  test('taps are parsed', () async {
    expect(
      await LiveTimerWidget.initialTap,
      LiveTimerTap(
        target: LiveTimerTapTarget.action,
        link: Uri.parse('app://fast'),
      ),
    );
    expect(
      await LiveTimerWidget.taps.first,
      const LiveTimerTap(target: LiveTimerTapTarget.widget),
    );
  });

  test('image file names are stable and distinct', () {
    const a = WidgetImage.asset('assets/a.png');
    expect(a.fileName, const WidgetImage.asset('assets/a.png').fileName);
    expect(a.fileName, isNot(const WidgetImage.asset('assets/b.png').fileName));
    expect(
      a.fileName,
      isNot(const WidgetImage.asset('assets/a.png', maxSize: 100).fileName),
    );
    expect(a.fileName, matches(RegExp(r'^ltw_[0-9a-f]{8}\.png$')));
  });
}
