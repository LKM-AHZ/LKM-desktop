import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Exercise the shared IO implementation without loading an ARM64 library on the host.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/utils/ohos_asset_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test(
    'OHOS asset extraction waits, preserves byte views and retries failures',
    () async {
      var requests = 0;
      var available = true;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        requests++;
        final encodedName = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        final name = Uri.decodeComponent(encodedName);
        expect(name, anyOf('assets/视频.mp4', 'assets/retry.mp4'));
        if (!available) return null;
        final bytes = Uint8List.fromList([99, 1, 2, 3, 88]);
        return ByteData.view(bytes.buffer, 1, 3);
      });
      final directories = <Directory>{};
      try {
        final results = await Future.wait([
          OhosAssetLoader.load('asset://assets/视频.mp4'),
          OhosAssetLoader.load('asset://assets/视频.mp4'),
        ]);
        expect(results[0], results[1]);
        expect(requests, 1);
        directories.add(File(results[0]).parent);
        expect(await File(results[0]).readAsBytes(), [1, 2, 3]);
        await File(results[0]).delete();
        final recreatedPaths = await Future.wait([
          OhosAssetLoader.load('asset://assets/视频.mp4'),
          OhosAssetLoader.load('asset://assets/视频.mp4'),
        ]);
        expect(recreatedPaths[0], recreatedPaths[1]);
        final recreated = recreatedPaths.first;
        expect(requests, 2);
        directories.add(File(recreated).parent);
        expect(await File(recreated).readAsBytes(), [1, 2, 3]);
        available = false;
        await expectLater(
          OhosAssetLoader.load('asset://assets/retry.mp4'),
          throwsA(isA<FlutterError>()),
        );
        available = true;
        final retried = await OhosAssetLoader.load('asset://assets/retry.mp4');
        directories.add(File(retried).parent);
        expect(await File(retried).readAsBytes(), [1, 2, 3]);
        await expectLater(
          OhosAssetLoader.load('asset://../outside.mp4'),
          throwsArgumentError,
        );
      } finally {
        messenger.setMockMessageHandler('flutter/assets', null);
        for (final directory in directories) {
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
