import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geocoding_ohos/geocoding_ohos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'OHOS current factory preserves per-instance/request locales and numeric results',
    () async {
      final previous = GeocodingPlatformFactory.instance;
      GeocodingOhos.registerWith();
      const channel = MethodChannel('flutter.baseflow.com/geocoding');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (fail) {
          throw PlatformException(
            code: 'IO_ERROR',
            message: 'service unavailable',
          );
        }
        return switch (call.method) {
          'isPresent' => true,
          'locationFromAddress' => [
            {'latitude': 0, 'longitude': 120},
          ],
          _ => [
            {'locality': '杭州', 'country': '中国'},
          ],
        };
      });
      try {
        final cn = Geocoding(locale: const Locale('zh', 'CN'));
        final en = Geocoding(locale: const Locale('en', 'US'));
        expect(await cn.isPresent(), true);
        final location = (await cn.locationFromAddress('杭州')).single;
        expect(location.latitude, 0.0);
        expect(location.longitude, 120.0);
        expect(location.timestamp, isNull);
        expect((calls.last.arguments as Map)['localeIdentifier'], 'zh-CN');
        expect(
          (await en.placemarkFromAddress('Hangzhou')).single.locality,
          '杭州',
        );
        expect((calls.last.arguments as Map)['localeIdentifier'], 'en-US');
        await cn.placemarkFromCoordinates(0, 120, locale: const Locale('fr'));
        expect((calls.last.arguments as Map)['localeIdentifier'], 'fr');
        await cn.placemarkFromCoordinates(0, 120);
        expect((calls.last.arguments as Map)['localeIdentifier'], 'zh-CN');
        fail = true;
        await expectLater(
          cn.locationFromAddress('unknown'),
          throwsA(isA<PlatformException>()),
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        if (previous != null) GeocodingPlatformFactory.instance = previous;
      }
    },
  );
}
