import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:huawei_push/huawei_push.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:logging/logging.dart';

/// Separable from host detection so lifecycle races can run in Flutter tests.
final huaweiPushPlatformProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.operatingSystem == 'ohos',
);

/// Watch once from the app's root Consumer. Uses the LKM session and API envelope,
/// independently of the legacy Firebase/Solian notification bootstrap.
final huaweiPushRegistrationProvider = Provider<void>((ref) {
  if (!ref.watch(huaweiPushPlatformProvider)) return;
  var disposed = false;
  Future<void> queue = Future<void>.value();
  String? registeredToken;
  var identityGeneration = 0;

  Future<void> register(int generation) async {
    if (generation != identityGeneration || disposed) return;
    final session = ref.read(lkmApiSessionProvider);
    if (session.tokens == null || disposed) return;
    final revision = session.identityRevision;
    final token = await HuaweiPush.getToken();
    if (disposed ||
        generation != identityGeneration ||
        !identical(session, ref.read(lkmApiSessionProvider)) ||
        session.tokens == null ||
        session.identityRevision != revision) {
      return;
    }
    if (registeredToken == token) return;
    await session.client.post(
      '/notification/me/tokens',
      body: {'token': token, 'platform': 'huawei'},
    );
    if (!disposed && generation == identityGeneration) {
      registeredToken = token;
    }
  }

  void schedule(Future<void> Function() action) {
    queue = queue
        .then((_) async {
          if (!disposed) await action();
        })
        .catchError((Object error, StackTrace stack) {
          // Preserve the actual provider/server error (including unavailable config).
          Logger.root.warning(
            '[Huawei Push] Registration unavailable',
            error,
            stack,
          );
        });
  }

  ref.listen(
    lkmApiSessionProvider.select(
      (session) =>
          (session.serverUrl, session.identityRevision, session.tokens != null),
    ),
    (previous, next) {
      final generation = ++identityGeneration;
      registeredToken = null;
      schedule(() async {
        if (generation != identityGeneration) return;
        if (previous != null) await HuaweiPush.deleteToken();
        if (next.$3) await register(generation);
      });
    },
    fireImmediately: true,
  );
  final tokenUpdates = HuaweiPush.tokenUpdates.listen(
    (_) {
      final generation = identityGeneration;
      // Native updates queued before an account change may carry its old token.
      // Read the current Push Kit token after queued invalidation completes.
      schedule(() => register(generation));
    },
    onError: (Object error) =>
        Logger.root.warning('[Huawei Push] Token update failed', error),
  );
  final lifecycle = _HuaweiPushLifecycle(() {
    final generation = identityGeneration;
    schedule(() => register(generation));
  });
  WidgetsBinding.instance.addObserver(lifecycle);
  ref.onDispose(() {
    disposed = true;
    unawaited(tokenUpdates.cancel());
    WidgetsBinding.instance.removeObserver(lifecycle);
  });
});

class _HuaweiPushLifecycle extends WidgetsBindingObserver {
  _HuaweiPushLifecycle(this.onResume);
  final VoidCallback onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Explicit registration for the notification settings/debug action. Failure is
/// surfaced to the caller; no Huawei token is ever passed to the FCM endpoint.
Future<void> subscribeHuaweiPush(ApiClient client) async {
  final token = await HuaweiPush.getToken();
  await client.post(
    '/notification/me/tokens',
    body: {'token': token, 'platform': 'huawei'},
  );
}
