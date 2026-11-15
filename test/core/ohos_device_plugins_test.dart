import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:map_launcher/map_launcher_platform_interface.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';
import 'package:quick_actions/quick_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.ohos);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'current quick actions preserves cold/warm launch and shortcut payload',
    () async {
      const channel = MethodChannel('plugins.flutter.io/quick_actions');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getLaunchAction' ? 'chats' : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final events = <String>[];
      const quick = QuickActions();
      await quick.initialize(events.add);
      await quick.setShortcutItems([
        const ShortcutItem(type: 'compose_post', localizedTitle: 'New Post'),
      ]);
      expect(events, ['chats']);
      expect(
        (calls.last.arguments as List).single,
        containsPair('type', 'compose_post'),
      );
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('launch', 'explore'),
        ),
        (_) {},
      );
      expect(events, ['chats', 'explore']);
      await quick.clearShortcutItems();
      expect(calls.last.method, 'clearShortcutItems');
    },
  );
  test(
    'current map API keeps OHOS universal URLs and probes map schemes',
    () async {
      const channel = MethodChannel('map_launcher');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getInstalledMaps'
            ? {
                'installed': ['amap'],
                'undeclared': <String>[],
              }
            : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final platform = MapLauncherPlatform.instance;
      expect(platform.platform, isNull);
      expect(await platform.getInstalledMaps([MapApp.amap]), {'amap'});
      expect((calls.last.arguments as Map)['amap'], isNotNull);
      await platform.launch('https://maps.example/marker');
      expect(
        calls.last.arguments,
        containsPair('url', 'https://maps.example/marker'),
      );
    },
  );
  test(
    'current NFC API propagates service failures and OHOS tag stream',
    () async {
      const channel = MethodChannel('flutter_nfc_kit/method');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getNFCAvailability') return 'available';
        throw PlatformException(code: '404', message: 'NFC disabled');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await FlutterNfcKit.nfcAvailability, NFCAvailability.available);
      await expectLater(
        FlutterNfcKit.poll(),
        throwsA(isA<PlatformException>()),
      );
      const events = MethodChannel('flutter_nfc_kit/event');
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(events, null));
      final tag = FlutterNfcKit.tagStream.first;
      await Future<void>.delayed(Duration.zero);
      await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(
          '{"type":"iso7816","id":"0102","standard":"ISO14443"}',
        ),
        (_) {},
      );
      expect((await tag).id, '0102');
    },
  );
  test(
    'OHOS scanner accepts exact integral geometry without fractional padding',
    () async {
      final native = <Object?, Object?>{
        'rawValue': 'code',
        'format': BarcodeFormat.qrCode.rawValue,
        'type': 0,
        'size': <Object?, Object?>{'width': 20, 'height': 10},
        'corners': <Object?>[
          <Object?, Object?>{'x': 0, 'y': 0},
          <Object?, Object?>{'x': 20, 'y': 10},
        ],
      };
      final barcode = Barcode.fromNative(native);
      expect(barcode.size.width, 20.0);
      expect(barcode.corners.first.dx, 0.0);
      const channel = MethodChannel(
        'dev.steenbakker.mobile_scanner/scanner/event',
      );
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final scanner = MethodChannelMobileScanner();
      final capture = scanner.barcodesStream.first;
      await Future<void>.delayed(Duration.zero);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'name': 'barcode',
          'data': [native],
          'image': {'width': 20, 'height': 10},
        }),
        (_) {},
      );
      expect((await capture)!.barcodes.single.rawValue, 'code');
    },
  );
}
