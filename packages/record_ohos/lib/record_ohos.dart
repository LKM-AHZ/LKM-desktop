import 'package:flutter/services.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
// Reuse the current interface's transport; it is not exported by the public barrel.
// ignore: implementation_imports
import 'package:record_platform_interface/src/record_platform.dart';

/// Reuse record 7's current method/event/configuration channels.
class RecordOhos extends RecordPlatformImpl {
  static void registerWith() => RecordPlatform.instance = RecordOhos();

  // The interface mixin drops this Future; cancellation must await native cleanup.
  @override
  Future<void> cancel(String recorderId) => const MethodChannel(
    'com.llfbandit.record/messages',
  ).invokeMethod<void>('cancel', {'recorderId': recorderId});

  // OHOS StandardMessageCodec encodes integral JS numbers as Dart ints.
  @override
  Future<Amplitude> getAmplitude(String recorderId) async {
    final values = await const MethodChannel(
      'com.llfbandit.record/messages',
    ).invokeMapMethod<String, num>('getAmplitude', {'recorderId': recorderId});
    return Amplitude(
      current: (values?['current'] ?? -160).toDouble(),
      max: (values?['max'] ?? -160).toDouble(),
    );
  }
}
