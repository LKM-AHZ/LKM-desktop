// Copyright © 2021 & onwards, Hitesh Kumar Saini. MIT; see LICENSE.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synchronized/synchronized.dart';
import '../platform_video_controller.dart';

/// Uses the OHOS libmpv OpenHarmony GPU context and the engine's surface texture.
class OhosVideoController extends PlatformVideoController {
  static bool get supported => Platform.operatingSystem == 'ohos';
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
  OhosVideoController._(super.player, super.configuration, this.handle);
  final int handle;
  final _lock = Lock();
  StreamSubscription<VideoParams>? _subscription;
  bool _disposed = false;
  int? _width;
  int? _height;
  NativePlayer get _native => player.platform as NativePlayer;

  Future<void> _property(String name, String value) =>
      _native.setProperty(name, value, waitForInitialization: false);

  static Future<PlatformVideoController> create(
      Player player, VideoControllerConfiguration configuration) async {
    final handle = await player.handle;
    final controller = OhosVideoController._(
        player,
        configuration.copyWith(
          vo: configuration.vo ?? 'gpu',
          hwdec: configuration.hwdec ??
              (configuration.enableHardwareAcceleration ? 'auto-safe' : 'no'),
        ),
        handle);
    controller._width = configuration.width;
    controller._height = configuration.height;
    try {
      final surface = await _channel.invokeMapMethod<String, Object?>(
          'VideoOutputManager.Create', {'handle': handle.toString()});
      final texture = (surface!['id'] as num).toInt();
      final wid = surface['wid'].toString();
      controller.id.value = texture;
      // The surface must exist before --vo=gpu is initialized.
      await controller._property('vo', 'null');
      await controller._property('gpu-context', 'openharmony');
      await controller._property('opengl-es', 'yes');
      await controller._property('wid', wid);
      await controller._property('hwdec', controller.configuration.hwdec!);
      await controller._property('vo', controller.configuration.vo!);
      await controller._property('vid', 'auto');
      controller._subscription = player.stream.videoParams.listen((params) {
        controller._lock
            .synchronized(() => controller._resize(params))
            .catchError((Object error, StackTrace stack) {
          debugPrint('OHOS video resize failed: $error');
        });
      });
      player.platform?.release.add(controller._dispose);
      return controller;
    } catch (_) {
      await controller._dispose();
      rethrow;
    }
  }

  Future<void> _resize(VideoParams params) async {
    if (_disposed) {
      return;
    }
    final rotate = params.rotate ?? 0;
    final videoWidth = (rotate == 90 || rotate == 270) ? params.dh : params.dw;
    final videoHeight = (rotate == 90 || rotate == 270) ? params.dw : params.dh;
    if (videoWidth == null ||
        videoHeight == null ||
        videoWidth <= 0 ||
        videoHeight <= 0) return;
    final width =
        _width ?? (videoWidth * configuration.scale).round().clamp(1, 16384);
    final height =
        _height ?? (videoHeight * configuration.scale).round().clamp(1, 16384);
    if (rect.value?.width == width && rect.value?.height == height) return;
    await _channel.invokeMethod<void>('VideoOutputManager.SetSurfaceSize', {
      'handle': handle.toString(),
      'width': width,
      'height': height,
    });
    await _property('openharmony-surface-size', '${width}x$height');
    rect.value = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  }

  @override
  Future<void> setSize({int? width, int? height}) =>
      _lock.synchronized(() async {
        if ((width != null && (width <= 0 || width > 16384)) ||
            (height != null && (height <= 0 || height > 16384))) {
          throw ArgumentError('Video surface dimensions must be in 1..16384');
        }
        _width = width;
        _height = height;
        await _resize(player.state.videoParams);
      });

  // The current OH-Flutter surface API has no frame-consumed callback.
  @override
  Future<void> get waitUntilFirstFrameRendered => Future.error(
        UnsupportedError(
            'OHOS does not expose a first-rendered-frame callback'),
      );

  Future<void> _dispose() => _lock.synchronized(() async {
        if (_disposed) {
          return;
        }
        _disposed = true;
        await _subscription?.cancel();
        try {
          await _channel.invokeMethod<void>(
              'VideoOutputManager.Dispose', {'handle': handle.toString()});
        } finally {
          super.dispose();
        }
      });
}
