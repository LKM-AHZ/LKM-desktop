// Copyright © 2021 & onwards, Hitesh Kumar Saini. MIT; see LICENSE.
import 'dart:io';
import 'package:flutter/services.dart';

/// OHOS assets live in the HAP. Extract before passing a filename to libmpv.
abstract class OhosAssetLoader {
  static final _loaded = <String, Future<String>>{};

  static Future<String> resolve(String uri) async {
    if (Platform.operatingSystem == 'ohos' && uri.startsWith('asset://')) {
      return await load(uri);
    }
    return uri;
  }

  static Future<String> load(String uri) async {
    final existing = _loaded[uri];
    if (existing != null) {
      final file = await existing;
      if (await File(file).exists()) return file;
      if (identical(_loaded[uri], existing)) {
        _loaded.remove(uri);
      } else {
        return load(uri);
      }
    }
    final operation = _extract(uri);
    _loaded[uri] = operation;
    try {
      return await operation;
    } catch (_) {
      if (identical(_loaded[uri], operation)) _loaded.remove(uri);
      rethrow;
    }
  }

  static Future<String> _extract(String uri) async {
    final raw = uri.substring('asset://'.length);
    // Normalize raw Unicode while preserving existing percent escapes, then decode once.
    final key = Uri.decodeComponent(Uri.encodeFull(raw).replaceAll('%25', '%'));
    if (key.isEmpty ||
        key.startsWith('/') ||
        key.contains('\\') ||
        key.contains('\x00') ||
        key.split('/').any((part) => part == '..')) {
      throw ArgumentError.value(uri, 'uri', 'Invalid Flutter asset key');
    }
    final data = await rootBundle.load(key);
    // The engine initializes Directory.systemTemp to the app cache directory.
    final directory = await Directory.systemTemp.createTemp('media-kit-asset-');
    final file = File('${directory.path}/${key.split('/').last}');
    try {
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return file.path;
    } catch (_) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }
}
