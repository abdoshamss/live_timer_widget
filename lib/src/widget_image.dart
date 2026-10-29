import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// An image shown by the home-screen widget.
///
/// The widget runs in another process (the launcher on Android, a WidgetKit
/// extension on iOS) and can't reach Flutter's assets or network cache, so
/// every image is decoded here, downscaled to [maxSize] and stored as a PNG
/// file the widget reads. An image already stored under the same
/// [cacheKey] is not encoded again.
///
/// Keep [maxSize] modest: Android limits the bitmap memory a widget may use,
/// and iOS kills an extension that goes over ~30 MB.
sealed class WidgetImage {
  const WidgetImage({this.maxSize = defaultMaxSize});

  /// A Flutter asset, e.g. `assets/images/plant.png`.
  const factory WidgetImage.asset(String name, {String? package, int maxSize}) =
      AssetWidgetImage;

  /// A file on the device.
  const factory WidgetImage.file(String path, {int maxSize}) = FileWidgetImage;

  /// An `http`/`https` image, downloaded once.
  const factory WidgetImage.network(
    String url, {
    Map<String, String> headers,
    int maxSize,
  }) = NetworkWidgetImage;

  /// Encoded image bytes (PNG, JPEG, WebP, …).
  const factory WidgetImage.memory(Uint8List bytes, {int maxSize}) =
      MemoryWidgetImage;

  /// Any [ImageProvider], e.g. a `CachedNetworkImageProvider`. Give it a
  /// [cacheKey] that changes whenever the image does; the provider's
  /// `toString()` is used otherwise.
  const factory WidgetImage.provider(
    ImageProvider provider, {
    String? cacheKey,
    int maxSize,
  }) = ProviderWidgetImage;

  /// Longest side, in pixels, the image is stored at.
  static const int defaultMaxSize = 720;

  final int maxSize;

  /// Identifies the stored file; equal keys share one file.
  String get cacheKey;

  /// The image's encoded bytes, before downscaling.
  Future<Uint8List> load();

  /// The stored file's name, stable across launches.
  String get fileName => 'ltw_${_fnv1a('$cacheKey@$maxSize')}.png';

  /// Decodes, downscales to fit [maxSize] and re-encodes as PNG.
  Future<Uint8List> encode() async {
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(await load()),
      getTargetSize: (width, height) {
        final longest = width > height ? width : height;
        if (longest <= maxSize) return ui.TargetImageSize(width: width);
        final scale = maxSize / longest;
        return ui.TargetImageSize(
          width: (width * scale).round(),
          height: (height * scale).round(),
        );
      },
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) throw StateError('Could not encode $cacheKey');
    return data.buffer.asUint8List();
  }
}

final class AssetWidgetImage extends WidgetImage {
  const AssetWidgetImage(this.name, {this.package, super.maxSize});

  final String name;
  final String? package;

  String get _key => package == null ? name : 'packages/$package/$name';

  @override
  String get cacheKey => 'asset:$_key';

  @override
  Future<Uint8List> load() async =>
      (await rootBundle.load(_key)).buffer.asUint8List();
}

final class FileWidgetImage extends WidgetImage {
  const FileWidgetImage(this.path, {super.maxSize});

  final String path;

  /// The modification time is part of the key, so an overwritten file is
  /// stored again.
  @override
  String get cacheKey {
    final file = File(path);
    final modified = file.existsSync()
        ? file.lastModifiedSync().millisecondsSinceEpoch
        : 0;
    return 'file:$path:$modified';
  }

  @override
  Future<Uint8List> load() => File(path).readAsBytes();
}

final class NetworkWidgetImage extends WidgetImage {
  const NetworkWidgetImage(this.url, {this.headers = const {}, super.maxSize});

  final String url;
  final Map<String, String> headers;

  @override
  String get cacheKey => 'network:$url';

  @override
  Future<Uint8List> load() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }
}

final class MemoryWidgetImage extends WidgetImage {
  const MemoryWidgetImage(this.bytes, {super.maxSize});

  final Uint8List bytes;

  @override
  String get cacheKey => 'memory:${bytes.length}:${_fnv1aBytes(bytes)}';

  @override
  Future<Uint8List> load() async => bytes;
}

final class ProviderWidgetImage extends WidgetImage {
  const ProviderWidgetImage(this.provider, {String? cacheKey, super.maxSize})
    : _cacheKey = cacheKey;

  final ImageProvider provider;
  final String? _cacheKey;

  @override
  String get cacheKey => 'provider:${_cacheKey ?? provider.toString()}';

  /// Resolves through Flutter's image pipeline, then re-encodes the frame.
  @override
  Future<Uint8List> load() async {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image.clone());
        info.dispose();
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        completer.completeError(error, stackTrace);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Could not encode $cacheKey');
    return data.buffer.asUint8List();
  }
}

String _fnv1a(String input) => _fnv1aBytes(utf8.encode(input));

/// 32-bit FNV-1a, hex. Enough to name files; not a security hash.
String _fnv1aBytes(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
