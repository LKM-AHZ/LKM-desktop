import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:island/core/services/notify.huawei.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _ok() => ResponseBody.fromString(
  jsonEncode({'code': 0, 'message': 'ok', 'data': {}}),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lkm.huawei_push');

  for (final switchServer in [false, true]) {
    test(
      'late registration cannot poison ${switchServer ? 'server' : 'account'} cache',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final firstStarted = Completer<void>();
        final completeFirst = Completer<void>();
        final secondStarted = Completer<void>();
        var posts = 0;
        var deletions = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'deleteToken') {
            deletions++;
            return null;
          }
          // Deliberately unchanged: correctness must not rely on SDK rotation.
          return 'same-huawei-token';
        });
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            huaweiPushPlatformProvider.overrideWithValue(true),
            lkmApiSessionProvider.overrideWith((ref) {
              final server = ref.watch(lkmServerUrlProvider);
              final session = ApiSession(
                prefs: prefs,
                serverUrl: server,
                onIdentityChanged: ref.notifyListeners,
                dio: Dio()
                  ..httpClientAdapter = _Adapter((request) async {
                    expect(request.path, '/notification/me/tokens');
                    posts++;
                    if (posts == 1) {
                      firstStarted.complete();
                      await completeFirst.future;
                    } else if (!secondStarted.isCompleted) {
                      secondStarted.complete();
                    }
                    return _ok();
                  }),
              );
              ref.onDispose(session.dispose);
              return session;
            }),
          ],
        );
        final subscription = container.listen(
          huaweiPushRegistrationProvider,
          (_, _) {},
        );
        try {
          await container
              .read(lkmApiSessionProvider)
              .adopt(const LkmTokenPair(accessToken: 'account-A'));
          await firstStarted.future;
          if (switchServer) {
            container
                .read(lkmServerUrlProvider.notifier)
                .setServer('https://other.example');
          }
          await container
              .read(lkmApiSessionProvider)
              .adopt(const LkmTokenPair(accessToken: 'account-B'));
          completeFirst.complete();
          await secondStarted.future.timeout(const Duration(seconds: 2));
          expect(posts, 2);
          expect(deletions, greaterThanOrEqualTo(1));
        } finally {
          subscription.close();
          container.dispose();
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
    );
  }
}
