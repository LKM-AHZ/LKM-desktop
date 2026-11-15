import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/passkeys.dart';
import 'package:passkeys/types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'OHOS passkeys use current public API and preserve challenge/response bytes',
    () async {
      PasskeysOhos.registerWith();
      const channel = MethodChannel('lkm.passkeys/ohos');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'availability' => {'passkeys': true, 'userVerification': true},
          'register' =>
            '{"id":"cred","rawId":"cred","response":{"clientDataJson":"client","attestationObject":"attestation","transports":["internal"]}}',
          'authenticate' =>
            '{"id":"cred","rawId":"cred","response":{"clientDataJson":"client","authenticatorData":"auth","signature":"signature","userHandle":"user"}}',
          _ => null,
        };
      });
      try {
        final authenticator = PasskeyAuthenticator(debugMode: false);
        final availability = await authenticator.getAvailability().ohos();
        expect(availability.isNative, true);
        expect(availability.hasPasskeySupport, true);
        final registration = await authenticator.register(
          RegisterRequestType.fromJson({
            'challenge': 'AQID',
            'rp': {'id': 'example.org', 'name': 'Example'},
            'user': {'id': 'BAUG', 'name': 'user', 'displayName': 'User'},
            'pubKeyCredParams': [
              {'type': 'public-key', 'alg': -7},
            ],
          }),
        );
        expect(registration.clientDataJSON, 'client');
        expect(registration.attestationObject, 'attestation');
        final args = Map<Object?, Object?>.from(calls.last.arguments as Map);
        expect(args['challenge'], Uint8List.fromList([1, 2, 3]));
        expect((args['user'] as Map)['id'], Uint8List.fromList([4, 5, 6]));
        final request = AuthenticateRequestType(
          challenge: 'AQID',
          relyingPartyId: 'example.org',
          mediation: MediationType.Optional,
          preferImmediatelyAvailableCredentials: false,
        );
        final response = await authenticator.authenticate(request);
        expect(response.clientDataJSON, 'client');
        expect(response.signature, 'signature');
        expect(response.authenticatorData, 'auth');
        expect((calls.last.arguments as Map)['rpId'], 'example.org');
        await expectLater(
          authenticator.authenticate(
            AuthenticateRequestType(
              challenge: 'AQID',
              relyingPartyId: 'example.org',
              mediation: MediationType.Conditional,
              preferImmediatelyAvailableCredentials: false,
            ),
          ),
          throwsUnsupportedError,
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
