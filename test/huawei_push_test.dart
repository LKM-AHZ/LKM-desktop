import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huawei_push/huawei_push.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lkm.huawei_push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uses native Push Kit token and forwards refresh events', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => 'huawei-token');
    expect(await HuaweiPush.getToken(), 'huawei-token');
    final refreshed = HuaweiPush.tokenUpdates.first;
    await messenger.handlePlatformMessage(
      'lkm.huawei_push',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('tokenUpdate', 'rotated-huawei-token'),
      ),
      (_) {},
    );
    expect(await refreshed, 'rotated-huawei-token');
  });

  test('empty token and native registration errors are surfaced', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => '');
    await expectLater(HuaweiPush.getToken(), throwsA(isA<PlatformException>()));
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'huawei_push_error',
        message: 'Invalid application identity',
        details: 1000900010,
      );
    });
    await expectLater(
      HuaweiPush.getToken(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.details,
          'native code',
          1000900010,
        ),
      ),
    );
  });
}
