import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:island/route.gr.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'message': 'ok',
        'data': {'email': options.data?['email'], 'message': 'sent'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _StubRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: RegisterRoute.page, path: '/auth/register', initial: true),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('email-only mode requests a code from the merged flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://community.example'))
      ..httpClientAdapter = adapter;
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://community.example',
      dio: dio,
      refreshDio: dio,
    );
    addTearDown(session.client.close);
    final config = _StubRouter().config();

    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            lkmApiSessionProvider.overrideWithValue(session),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en', 'US')],
            path: 'assets/i18n',
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp.router(
                locale: const Locale('en', 'US'),
                supportedLocales: const [Locale('en', 'US')],
                localizationsDelegates: context.localizationDelegates,
                routerConfig: config,
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Email only'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'alma@example.com',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(adapter.requests.single.path, contains('/auth/reg/email'));
    expect(adapter.requests.single.data, {'email': 'alma@example.com'});
    // The code field only appears once the server accepted the request.
    expect(find.widgetWithText(TextField, 'Email code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
