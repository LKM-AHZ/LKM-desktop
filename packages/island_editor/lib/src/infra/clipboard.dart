import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IslandClipboardData {
  const IslandClipboardData({
    this.text,
    this.html,
  });
  final String? text;
  final String? html;
}

class IslandClipboard {
  static IslandClipboardData? _mockData;

  @visibleForTesting
  static String? lastText;

  static Future<void> setData({
    String? text,
    String? html,
  }) async {
    if (text == null) {
      return;
    }

    lastText = text;

    return Clipboard.setData(
      ClipboardData(
        text: text,
      ),
    );
  }

  static Future<IslandClipboardData> getData() async {
    if (_mockData != null) {
      return _mockData!;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return IslandClipboardData(
      text: data?.text,
      html: null,
    );
  }

  @visibleForTesting
  static void mockSetData(IslandClipboardData? data) {
    _mockData = data;
  }
}
