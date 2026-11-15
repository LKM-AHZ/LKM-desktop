import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:record_ohos/record_ohos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.llfbandit.record/messages');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'OHOS uses record 7 config, state/data channels and awaits cancellation',
    () async {
      final original = RecordPlatform.instance;
      RecordOhos.registerWith();
      final calls = <MethodCall>[];
      final nativeEvents = <String>[];
      Completer<void>? cancelGate;
      var integralAmplitude = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final id = args['recorderId'] as String;
        if (call.method == 'create') {
          for (final suffix in ['events', 'eventsRecord']) {
            final name = 'com.llfbandit.record/$suffix/$id';
            nativeEvents.add(name);
            messenger.setMockMethodCallHandler(
              MethodChannel(name),
              (_) async => null,
            );
          }
        }
        return switch (call.method) {
          'hasPermission' => false,
          'isEncoderSupported' => args['encoder'] == 'wav',
          'getAmplitude' =>
            integralAmplitude
                ? <String, num>{'current': -160, 'max': 0}
                : <String, num>{'current': -6.0, 'max': 0.0},
          'listInputDevices' => <Object>[],
          'stop' => '/tmp/voice.wav',
          'cancel' => await cancelGate?.future,
          _ => null,
        };
      });
      final recorder = AudioRecorder();
      try {
        expect(await recorder.hasPermission(request: false), false);
        expect((calls.last.arguments as Map)['request'], false);
        expect(await recorder.isEncoderSupported(AudioEncoder.wav), true);
        expect(await recorder.isEncoderSupported(AudioEncoder.flac), false);
        final states = <RecordState>[];
        final stateSub = recorder.onStateChanged().listen(states.add);
        const config = RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 48000,
        );
        await recorder.start(config, path: '/tmp/voice.wav');
        final start = calls.firstWhere((call) => call.method == 'start');
        expect(start.arguments, containsPair('path', '/tmp/voice.wav'));
        for (final entry in config.toMap().entries) {
          expect(start.arguments, containsPair(entry.key, entry.value));
        }
        final id = (start.arguments as Map)['recorderId'];
        await messenger.handlePlatformMessage(
          'com.llfbandit.record/events/$id',
          codec.encodeSuccessEnvelope(1),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(states, contains(RecordState.record));
        expect((await recorder.getAmplitude()).current, -6.0);
        integralAmplitude = true;
        final silent = await recorder.getAmplitude();
        expect(silent.current, -160.0);
        expect(silent.max, 0.0);
        expect(await recorder.listInputDevices(), isEmpty);
        RecordConfig? adjusted;
        await recorder.setOnConfigChanged((config) => adjusted = config);
        await messenger.handlePlatformMessage(
          'com.llfbandit.record/configChanged/$id',
          codec.encodeMethodCall(MethodCall('onConfigChanged', config.toMap())),
          (_) {},
        );
        expect(adjusted?.sampleRate, 48000);
        await recorder.pause();
        await recorder.resume();
        expect(await recorder.stop(), '/tmp/voice.wav');

        final stream = await recorder.startStream(
          const RecordConfig(encoder: AudioEncoder.pcm16bits),
        );
        final bytes = <int>[];
        final streamSub = stream.listen(bytes.addAll);
        await Future<void>.delayed(Duration.zero);
        await messenger.handlePlatformMessage(
          'com.llfbandit.record/eventsRecord/$id',
          codec.encodeSuccessEnvelope(Uint8List.fromList([0, 1, 2, 3])),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(bytes, [0, 1, 2, 3]);
        cancelGate = Completer<void>();
        var cancelled = false;
        final cancelling = recorder.cancel().then((_) => cancelled = true);
        await Future<void>.delayed(Duration.zero);
        expect(cancelled, false);
        cancelGate.complete();
        await cancelling;
        expect(cancelled, true);
        await streamSub.cancel();
        await stateSub.cancel();
        await recorder.setOnConfigChanged(null);
      } finally {
        await recorder.dispose();
        RecordPlatform.instance = original;
        messenger.setMockMethodCallHandler(channel, null);
        for (final name in nativeEvents) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      }
    },
  );

  test(
    'OHOS forwards microphone/start failures instead of claiming success',
    () async {
      final original = RecordPlatform.instance;
      RecordOhos.registerWith();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'start') {
          throw PlatformException(
            code: 'record_error',
            message: 'prepare failed',
          );
        }
        return null;
      });
      try {
        await RecordPlatform.instance.create('failure');
        await expectLater(
          RecordPlatform.instance.start(
            'failure',
            const RecordConfig(),
            path: '/tmp/failure.m4a',
          ),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.message,
              'message',
              'prepare failed',
            ),
          ),
        );
      } finally {
        RecordPlatform.instance = original;
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
