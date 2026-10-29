import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'live_timer.dart';
import 'platform.dart';
import 'style.dart';
import 'widget_image.dart';

/// Which part of the widget was tapped.
enum LiveTimerTapTarget {
  /// Anywhere on the widget.
  widget,

  /// The idle [LiveTimerIdle.actionLabel] button.
  action,
}

/// A tap on the home-screen widget that opened the app.
@immutable
class LiveTimerTap {
  const LiveTimerTap({required this.target, this.link});

  final LiveTimerTapTarget target;

  /// The [LiveTimer.link], [LiveTimerIdle.link] or [LiveTimerIdle.actionLink]
  /// of what was showing.
  final Uri? link;

  static LiveTimerTap? _fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    final link = map['link'] as String?;
    return LiveTimerTap(
      target: map['target'] == 'action'
          ? LiveTimerTapTarget.action
          : LiveTimerTapTarget.widget,
      link: link == null || link.isEmpty ? null : Uri.tryParse(link),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveTimerTap && other.target == target && other.link == link;

  @override
  int get hashCode => Object.hash(target, link);

  @override
  String toString() => 'LiveTimerTap($target, $link)';
}

/// A live timer on the home screen (Android app widget, iOS WidgetKit home
/// and lock screen widget).
///
/// ```dart
/// await LiveTimerWidget.initialize(iOSAppGroupId: 'group.com.example.app');
/// await LiveTimerWidget.configure(
///   style: const LiveTimerStyle(accent: Colors.lime),
///   idle: const LiveTimerIdle(title: 'Ready?', actionLabel: 'Start'),
/// );
/// await LiveTimerWidget.start(LiveTimer(
///   startedAt: DateTime.now(),
///   goal: const Duration(hours: 16),
///   title: 'Fasting · {percent}',
/// ));
/// ```
///
/// The widget never calls back into Dart: everything it shows is written
/// here, and its clock runs natively. Every call is safe from a background
/// isolate (e.g. a push handler) once [initialize] has run in any isolate.
///
/// Calls are serialized, so they apply in the order they were made.
abstract final class LiveTimerWidget {
  static LiveTimerWidgetPlatform get _platform =>
      LiveTimerWidgetPlatform.instance;

  /// The `kind` of the iOS widget, as set by `setup_ios`.
  static const String defaultIOSWidgetKind = 'LiveTimerWidget';

  static const int _schemaVersion = 1;

  /// The last state written by this isolate.
  static Map<String, Object?>? _state;
  static Future<void> _queue = Future.value();

  /// Required on iOS before anything else: [iOSAppGroupId] is the App Group
  /// shared by the app and its widget extension. Android ignores both
  /// arguments.
  static Future<void> initialize({
    String? iOSAppGroupId,
    String iOSWidgetKind = defaultIOSWidgetKind,
  }) => _serial(
    () => _platform.initialize(
      appGroupId: iOSAppGroupId,
      widgetKind: iOSWidgetKind,
    ),
  );

  /// Sets what the widget looks like ([style]), what it shows with no timer
  /// ([idle]) and its layout direction. A `null` argument keeps the stored
  /// value; [textDirection] defaults to the device locale's.
  static Future<void> configure({
    LiveTimerStyle? style,
    LiveTimerIdle? idle,
    TextDirection? textDirection,
  }) => _serial(() async {
    final state = await _loadState();
    if (style != null) state['style'] = style.toJson();
    if (idle != null) {
      state['idle'] = idle.toJson(await _storeImages([?idle.image]));
    }
    if (textDirection != null) {
      state['rtl'] = textDirection == TextDirection.rtl;
    }
    await _save(state);
  });

  /// Shows [timer] until [stop], or until it ends by itself
  /// ([LiveTimer.maxDuration], [TimerCompletion.idle]).
  static Future<void> start(LiveTimer timer) => _serial(() async {
    final state = await _loadState();
    state['timer'] = timer.toJson(await _storeImages(timer.images));
    await _save(state);
  });

  /// Back to the idle content. The style and idle content are kept.
  static Future<void> stop() => _serial(() async {
    final state = await _loadState();
    if (state['timer'] == null) return;
    state['timer'] = null;
    await _save(state);
  });

  /// Wipes everything, including stored images; the widget shows its
  /// defaults. Use it on logout.
  static Future<void> reset() => _serial(() async {
    _state = {'version': _schemaVersion};
    await _save(_state!);
  });

  /// Whether the widget currently shows a timer (running or completed) rather
  /// than the idle content.
  static Future<bool> get isRunning async {
    await _queue;
    final timer = (await _loadState())['timer'] as Map<String, Object?>?;
    if (timer == null) return false;
    final startMs = timer['startMs'] as int;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxMs = timer['maxMs'] as int?;
    final endMs = timer['endMs'] as int?;
    if (maxMs != null && now - startMs >= maxMs) return false;
    return !(endMs != null && now >= endMs && timer['completion'] == 'idle');
  }

  /// Widgets of this app currently placed on the home or lock screen.
  static Future<int> get installedCount => _platform.installedCount();

  /// Whether [requestPin] can show the system "add widget" prompt (Android 8+
  /// on a launcher that supports it; never on iOS).
  static Future<bool> get isPinSupported => _platform.isPinSupported();

  /// Asks the launcher to place the widget. Returns whether the prompt was
  /// shown, not whether the user accepted — watch [installedCount] for that.
  static Future<bool> requestPin() => _platform.requestPin();

  /// The tap that launched the app, if it was launched from the widget.
  /// Read once: later calls return `null`.
  static Future<LiveTimerTap?> get initialTap async =>
      LiveTimerTap._fromMap(await _platform.initialTap());

  /// Taps on the widget while the app is running or in the background.
  static Stream<LiveTimerTap> get taps =>
      _platform.taps().map((map) => LiveTimerTap._fromMap(map)!);

  static Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Always read back from the native store: another isolate (a push
  /// handler) may have written since.
  static Future<Map<String, Object?>> _loadState() async {
    final raw = await _platform.load();
    Map<String, Object?>? decoded;
    if (raw != null && raw.isNotEmpty) {
      try {
        decoded = (jsonDecode(raw) as Map).cast<String, Object?>();
      } on FormatException {
        decoded = null;
      }
    }
    return _state = decoded ?? {'version': _schemaVersion};
  }

  static Future<void> _save(Map<String, Object?> state) async {
    state['version'] = _schemaVersion;
    state['updatedMs'] = DateTime.now().millisecondsSinceEpoch;
    _state = state;
    await _platform.save(jsonEncode(state));
    await _platform.pruneImages(_referencedImages(state).toList());
  }

  /// Stores every image not stored yet; returns the file-name lookup the
  /// models serialize with.
  static Future<String? Function(WidgetImage?)> _storeImages(
    List<WidgetImage> images,
  ) async {
    final names = <WidgetImage, String>{};
    for (final image in images) {
      final name = image.fileName;
      try {
        if (!await _platform.hasImage(name)) {
          await _platform.saveImage(name, await image.encode());
        }
        names[image] = name;
      } catch (error, stack) {
        // A missing image must not keep the timer off the widget.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'live_timer_widget',
            context: ErrorDescription('storing ${image.cacheKey}'),
          ),
        );
      }
    }
    return (image) => image == null ? null : names[image];
  }

  static Iterable<String> _referencedImages(Map<String, Object?> state) sync* {
    final timer = state['timer'] as Map<String, Object?>?;
    final idle = state['idle'] as Map<String, Object?>?;
    for (final section in [?timer, ?idle]) {
      if (section['image'] case final String name) yield name;
    }
    for (final stage in (timer?['stages'] as List?) ?? const []) {
      if ((stage as Map)['image'] case final String name) yield name;
    }
  }

  /// Forgets the in-memory state, as a fresh isolate would.
  @visibleForTesting
  static void debugReset() {
    _state = null;
    _queue = Future.value();
  }

  /// The last state written, as stored natively.
  @visibleForTesting
  static Map<String, Object?>? get debugState => _state;
}
