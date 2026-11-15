import 'dart:async';
import 'package:flutter/services.dart';

/// Uses HarmonyOS NEXT Push Kit. Tokens must only be sent to a Huawei provider.
class HuaweiPush {
  static const _channel = MethodChannel('lkm.huawei_push');
  static final _tokens = StreamController<String>.broadcast();
  static final _messages = StreamController<String>.broadcast();
  static bool _initialized = false;

  static Stream<String> get tokenUpdates => _tokens.stream;
  static Stream<String> get foregroundMessages => _messages.stream;

  static Future<String> getToken() async {
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'tokenUpdate' && call.arguments is String) {
          _tokens.add(call.arguments as String);
        } else if (call.method == 'message' && call.arguments is String) {
          _messages.add(call.arguments as String);
        } else if (call.method == 'error') {
          _tokens.addError(PlatformException(
            code: 'huawei_push_error',
            message: '${call.arguments}',
          ));
        }
      });
    }
    final token = await _channel.invokeMethod<String>('getToken');
    if (token == null || token.isEmpty) {
      throw PlatformException(
          code: 'huawei_push_error', message: 'Empty Push Kit token');
    }
    return token;
  }

  static Future<void> deleteToken() =>
      _channel.invokeMethod<void>('deleteToken');
}
