import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The native side of [LiveTimerWidget]. Replace [instance] in tests.
abstract class LiveTimerWidgetPlatform extends PlatformInterface {
  LiveTimerWidgetPlatform() : super(token: _token);

  static final Object _token = Object();

  static LiveTimerWidgetPlatform _instance = MethodChannelLiveTimerWidget();

  static LiveTimerWidgetPlatform get instance => _instance;

  static set instance(LiveTimerWidgetPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// iOS: the App Group shared with the widget extension, and the widget's
  /// `kind`. Remembered natively, so a background isolate needn't repeat it.
  Future<void> initialize({String? appGroupId, required String widgetKind});

  /// The stored state JSON, or `null` before the first [save].
  Future<String?> load();

  /// Stores [state] and redraws every placed widget.
  Future<void> save(String state);

  Future<bool> hasImage(String name);

  Future<void> saveImage(String name, Uint8List png);

  /// Deletes every stored image not in [keep].
  Future<void> pruneImages(List<String> keep);

  Future<int> installedCount();

  Future<bool> isPinSupported();

  Future<bool> requestPin();

  /// The tap that launched the app, as `{link, target}`; consumed once read.
  Future<Map<Object?, Object?>?> initialTap();

  /// Taps while the app is running, as `{link, target}`.
  Stream<Map<Object?, Object?>> taps();
}

@visibleForTesting
class MethodChannelLiveTimerWidget extends LiveTimerWidgetPlatform {
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('live_timer_widget');

  @visibleForTesting
  static const EventChannel tapChannel = EventChannel('live_timer_widget/taps');

  @override
  Future<void> initialize({String? appGroupId, required String widgetKind}) =>
      channel.invokeMethod('initialize', {
        'appGroupId': appGroupId,
        'widgetKind': widgetKind,
      });

  @override
  Future<String?> load() => channel.invokeMethod<String>('load');

  @override
  Future<void> save(String state) =>
      channel.invokeMethod('save', {'state': state});

  @override
  Future<bool> hasImage(String name) async =>
      await channel.invokeMethod<bool>('hasImage', {'name': name}) ?? false;

  @override
  Future<void> saveImage(String name, Uint8List png) =>
      channel.invokeMethod('saveImage', {'name': name, 'bytes': png});

  @override
  Future<void> pruneImages(List<String> keep) =>
      channel.invokeMethod('pruneImages', {'keep': keep});

  @override
  Future<int> installedCount() async =>
      await channel.invokeMethod<int>('installedCount') ?? 0;

  @override
  Future<bool> isPinSupported() async =>
      await channel.invokeMethod<bool>('isPinSupported') ?? false;

  @override
  Future<bool> requestPin() async =>
      await channel.invokeMethod<bool>('requestPin') ?? false;

  @override
  Future<Map<Object?, Object?>?> initialTap() =>
      channel.invokeMethod<Map<Object?, Object?>>('initialTap');

  @override
  Stream<Map<Object?, Object?>> taps() => tapChannel
      .receiveBroadcastStream()
      .map((event) => event as Map<Object?, Object?>);
}
