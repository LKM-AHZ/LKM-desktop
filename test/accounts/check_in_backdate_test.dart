import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/accounts/check_in.dart';
import 'package:island/accounts/screens/check_in.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

Map<String, dynamic> _resultJson(DateTime day) => {
  'id': 'checkin-${day.toIso8601String()}',
  'level': 3,
  'tips': const <Map<String, dynamic>>[],
  'created_at': DateTime.utc(day.year, day.month, day.day).toIso8601String(),
  'fortune_report': {
    'version': 1,
    'poem': 'Rain on the old eaves.',
    'summary': 'A steady day.',
    'summary_detail': null,
    'wish': 'Ask plainly.',
    'love': 'Patience.',
    'study': 'Two quiet hours.',
    'career': 'Hold the thread.',
    'health': 'Stretch.',
    'lost_item': 'Under the second thing.',
    'lucky_color': 'Ink blue',
    'lucky_direction': 'Southwest',
    'lucky_time': 'Late afternoon',
    'lucky_item': 'A notebook',
    'lucky_action': 'Write it down.',
    'avoid_action': 'Reopening it.',
    'ritual': 'Pour the first cup.',
  },
};

Map<String, dynamic> _checkinEnvelope(DateTime day, {bool backdated = false}) =>
    {
      'code': 0,
      'message': 'ok',
      'data': {
        'success': true,
        'earned': 5,
        'checkin_streak': 1,
        'today_checked': false,
        'backdated': backdated,
        'result': _resultJson(day),
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<RequestOptions> requests,
  }) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://community.example'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method != 'POST' ||
              !options.path.endsWith('/points/checkin')) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ),
            );
            return;
          }
          requests.add(options);
          final raw = options.queryParameters['date'] as String?;
          final day = raw == null ? _day(DateTime.now()) : DateTime.parse(raw);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: _checkinEnvelope(
                day,
                backdated: options.queryParameters.containsKey('date'),
              ),
            ),
          );
        },
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://community.example',
      dio: dio,
    );
    await session.adopt(
      const LkmTokenPair(accessToken: 'access', refreshToken: 'refresh'),
    );
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
            lkmApiSessionProvider.overrideWithValue(session),
            checkInResultTodayProvider.overrideWith((ref) async => null),
            checkInHistoryProvider.overrideWith((ref, range) async => const {}),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en', 'US')],
            path: 'assets/i18n',
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                locale: const Locale('en', 'US'),
                supportedLocales: const [Locale('en', 'US')],
                localizationsDelegates: context.localizationDelegates,
                home: const Scaffold(body: CheckInScreen()),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('a past day can be filled in, and the draw targets that day', (
    tester,
  ) async {
    final yesterday = _day(DateTime.now().subtract(const Duration(days: 1)));
    final requests = <RequestOptions>[];
    await pumpSheet(tester, requests: requests);

    await tester.scrollUntilVisible(
      find.text('${yesterday.day}'),
      240,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${yesterday.day}'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Draw for this day'), findsOneWidget);

    await tester.ensureVisible(find.text('Draw for this day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw for this day'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(requests, hasLength(1));
    expect(
      requests.single.queryParameters['date'],
      yesterday.toIso8601String().substring(0, 10),
    );
    expect(find.byType(FortuneCard), findsOneWidget);
    expect(find.text('Draw for this day'), findsNothing);
    expect(find.text("Draw today's sign"), findsOneWidget);
  });

  testWidgets('today draws without a backdated date', (tester) async {
    final requests = <RequestOptions>[];
    await pumpSheet(tester, requests: requests);

    await tester.tap(find.text("Draw today's sign"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters.containsKey('date'), isFalse);
    expect(find.text("Draw today's sign"), findsNothing);
    expect(find.byType(FortuneCard), findsOneWidget);
  });
}
