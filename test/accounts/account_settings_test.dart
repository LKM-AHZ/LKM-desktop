import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/accounts/screens/me/account_settings.dart';
import 'package:island/accounts/screens/me/profile_update.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:island/route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AccountAdapter implements HttpClientAdapter {
  String nickname = 'Alice';
  bool failSettings = false;
  bool failPasskeys = false;
  bool failSave = false;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(request);
    Object? data;
    var code = 0;
    var message = 'ok';
    if (request.path.endsWith('/auth/settings')) {
      if (failSettings) {
        code = 50000;
        message = 'Settings unavailable';
      }
      data = {'email': 'alice@example.test', 'has_2fa': true};
    } else if (request.path.endsWith('/passkey/credentials')) {
      if (failPasskeys) {
        code = 50000;
        message = 'Passkeys unavailable';
      }
      data = <Object>[];
    } else if (request.path.endsWith('/profile') && request.method == 'PUT') {
      if (failSave) {
        code = 50000;
        message = 'Profile rejected';
      } else {
        nickname = '${(request.data as Map)['nickname']}';
      }
      data = {'user_id': 'user-1', 'nickname': nickname};
    } else if (request.path.endsWith('/auth/avatar')) {
      data = {'avatar': 'avatars/new.webp'};
    } else {
      data = {
        'id': 'user-1',
        'user_id': 'user-1',
        'username': 'alice',
        'nickname': nickname,
        'account_level': 'normal',
        'role': 'member',
      };
    }
    return ResponseBody.fromString(
      jsonEncode({'code': code, 'message': message, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _AccountAdapter adapter, {
  bool legacy = false,
}) async {
  tester.view.physicalSize = const Size(1100, 1150);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    apiTokenStoreKey('https://example.test'): jsonEncode({
      'access_token': 'test-token',
    }),
  });
  final prefs = await SharedPreferences.getInstance();
  final session = ApiSession(
    prefs: prefs,
    serverUrl: 'https://example.test',
    dio: Dio()..httpClientAdapter = adapter,
  );
  final owner = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lkmApiSessionProvider.overrideWithValue(session),
    ],
  );
  addTearDown(() {
    owner.dispose();
    session.dispose();
  });
  final router = AppRouter();
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: owner,
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: const [Locale('en', 'US')],
              locale: const Locale('en', 'US'),
              theme: ThemeData(splashFactory: InkRipple.splashFactory),
              home: RouterScope(
                controller: router,
                stateHash: 0,
                inheritableObserversBuilder: () => [],
                child: StackRouterScope(
                  controller: router,
                  stateHash: 0,
                  child: legacy
                      ? const AccountUpdateProfileScreen()
                      : const AccountSettingsScreen(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await _settle(tester);
  expect(tester.takeException(), isNull);
  return owner;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('nickname saves update this page and the cached public profile', (
    tester,
  ) async {
    final adapter = _AccountAdapter();
    final owner = await _pump(tester, adapter);
    await tester.runAsync(() async {
      final subscription = owner.listen(
        userProfileProvider('user-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await owner.read(userProfileProvider('user-1').future);
    });
    expect(
      adapter.requests.where((r) => r.path.endsWith('/auth/me')),
      hasLength(1),
    );
    await tester.tap(find.text('Nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Alice Chen  ');
    await tester.tap(find.text('Confirm'));
    await _settle(tester);
    expect(owner.read(lkmMeProvider).value!.nickname, 'Alice Chen');
    expect(
      owner.read(userProfileProvider('user-1')).value!.nickname,
      'Alice Chen',
    );
    expect(find.text('Alice Chen'), findsNWidgets(2));
    expect(adapter.requests.where((r) => r.method == 'PUT').single.data, {
      'nickname': 'Alice Chen',
    });
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'a rejected profile update keeps the previous identity and offers retry',
    (tester) async {
      final adapter = _AccountAdapter()..failSave = true;
      final owner = await _pump(tester, adapter);
      await tester.tap(find.text('Nickname'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Changed');
      await tester.tap(find.text('Confirm'));
      await _settle(tester);
      expect(find.text('Profile rejected'), findsOneWidget);
      expect(find.text('Alice'), findsNWidgets(2));
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('clearing a nickname restores the username display', (
    tester,
  ) async {
    final adapter = _AccountAdapter();
    final owner = await _pump(tester, adapter);
    await tester.tap(find.text('Nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Confirm'));
    await _settle(tester);
    expect(adapter.nickname, '');
    expect(find.text('alice'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('failed security reads stay unknown and recover through retry', (
    tester,
  ) async {
    final adapter = _AccountAdapter()..failSettings = true;
    final owner = await _pump(tester, adapter);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(find.text('Settings unavailable'), findsOneWidget);
    adapter.failSettings = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNotNull);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('passkey failures preserve loaded security and profile data', (
    tester,
  ) async {
    final owner = await _pump(tester, _AccountAdapter()..failPasskeys = true);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.text('Alice'), findsNWidgets(2));
    expect(find.text('Passkeys unavailable'), findsOneWidget);
    expect(find.text('Failed to load'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'legacy profile links load the current LKM profile without Solar identity',
    (tester) async {
      final adapter = _AccountAdapter();
      final owner = await _pump(tester, adapter, legacy: true);
      expect(find.byType(AccountSettingsScreen), findsOneWidget);
      expect(find.text('@alice'), findsOneWidget);
      expect(
        adapter.requests.any((r) => r.path.contains('/stargate')),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('changing sessions clears the previous account security state', (
    tester,
  ) async {
    final owner = await _pump(tester, _AccountAdapter());
    final prefs = owner.read(sharedPreferencesProvider);
    final otherSession = ApiSession(
      prefs: prefs,
      serverUrl: 'https://example.test',
      dio: Dio()
        ..httpClientAdapter = (_AccountAdapter()
          ..nickname = 'Bob'
          ..failSettings = true),
    );
    addTearDown(otherSession.dispose);
    owner.updateOverrides([
      sharedPreferencesProvider.overrideWithValue(prefs),
      lkmApiSessionProvider.overrideWithValue(otherSession),
    ]);
    await _settle(tester);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsNWidgets(2));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(find.text('Settings unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'avatar uploads reject oversize files and avoid a redundant profile write',
    (tester) async {
      final adapter = _AccountAdapter();
      final owner = await _pump(tester, adapter);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lkm-profile-'),
      ))!;
      final large = (await tester.runAsync(
        () => File(
          '${directory.path}/large.png',
        ).writeAsBytes(Uint8List(2 * 1024 * 1024 + 1)),
      ))!;
      final small = (await tester.runAsync(
        () => File('${directory.path}/small.png').writeAsBytes([1, 2, 3]),
      ))!;
      var picked = large;
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      final previous = FilePickerPlatform.instance;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => [picked.uri.toString()],
      );
      FilePickerOhos.registerWith();
      addTearDown(() async {
        FilePickerPlatform.instance = previous;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await directory.delete(recursive: true);
      });
      await tester.tap(find.text('Upload avatar'));
      await _settle(tester);
      expect(find.text('Choose an image no larger than 2 MB.'), findsOneWidget);
      expect(
        adapter.requests.any((r) => r.path.endsWith('/auth/avatar')),
        isFalse,
      );
      picked = small;
      await tester.tap(find.text('Upload avatar'));
      await _settle(tester);
      expect(
        adapter.requests.where((r) => r.path.endsWith('/auth/avatar')),
        hasLength(1),
      );
      expect(adapter.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
