import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'current RTC peer and renderer protocols work without a Dart surfaceId fork',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('FlutterWebRTC.Method');
      final calls = <MethodCall>[];
      final eventChannels = [
        'FlutterWebRTC.Event',
        'FlutterWebRTC/peerConnectionEventpeer',
        'FlutterWebRTC/Texture12',
      ];
      for (final name in eventChannels) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'createPeerConnection' => {'peerConnectionId': 'peer'},
          'createOffer' => {'sdp': 'offer-sdp', 'type': 'offer'},
          'createVideoRenderer' => {'textureId': 12},
          'createLocalMediaStream' => {'streamId': 'local'},
          'mediaStreamGetTracks' => {'audioTracks': [], 'videoTracks': []},
          _ => null,
        };
      });
      try {
        final connection = await createPeerConnection({
          'iceTransportPolicy': 'relay',
          'iceServers': [],
        });
        expect(
          (calls.firstWhere((c) => c.method == 'createPeerConnection').arguments
              as Map)['configuration'],
          containsPair('iceTransportPolicy', 'relay'),
        );
        expect((await connection.createOffer()).sdp, 'offer-sdp');
        final stream = await createLocalMediaStream('empty');
        expect(stream.id, 'local');
        expect(stream.getTracks(), isEmpty);
        await stream.dispose();
        await connection.setLocalDescription(
          RTCSessionDescription('offer-sdp', 'offer'),
        );
        await connection.setRemoteDescription(
          RTCSessionDescription('answer-sdp', 'answer'),
        );
        await connection.addCandidate(RTCIceCandidate('candidate', '0', 0));
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        expect(renderer.textureId, 12);
        await renderer.setSrcObject(stream: null);
        final args = calls.last.arguments as Map;
        expect(args['textureId'], 12);
        expect(args.containsKey('surfaceId'), false);
        await renderer.dispose();
        await connection.dispose();
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        for (final name in eventChannels) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      }
    },
  );
}
