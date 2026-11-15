import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';
import 'package:passkeys_platform_interface/types/types.dart';
import 'package:passkeys_platform_interface/types/credential.dart';

class PasskeysOhos extends PasskeysPlatform {
  static const _channel = MethodChannel('lkm.passkeys/ohos');
  static void registerWith() => PasskeysPlatform.instance = PasskeysOhos();
  Uint8List _bytes(String value) =>
      base64Url.decode(base64Url.normalize(value));
  List<Map<String, Object?>> _credentials(List<CredentialType>? credentials) =>
      (credentials ?? [])
          .map(
            (c) => <String, Object?>{
              'id': _bytes(c.id),
              'type': c.type,
              'transports': c.transports,
            },
          )
          .toList();
  @override
  Future<AvailabilityTypeOhos> getAvailability() async {
    final result = await _channel.invokeMapMethod<String, bool>('availability');
    return AvailabilityTypeOhos(
      hasPasskeySupport: result?['passkeys'] ?? false,
      isUserVerifyingPlatformAuthenticatorAvailable:
          result?['userVerification'] ?? false,
    );
  }

  @override
  Future<bool> canAuthenticate() async =>
      (await getAvailability()).hasPasskeySupport;
  @override
  Future<void> cancelCurrentAuthenticatorOperation() =>
      _channel.invokeMethod<void>('cancel');
  Map<String, dynamic> _response(String value) {
    final row = Map<String, dynamic>.from(jsonDecode(value) as Map);
    final response = Map<String, dynamic>.from(row['response'] as Map);
    response['clientDataJSON'] = response.remove('clientDataJson');
    row['response'] = response;
    return row;
  }

  @override
  Future<RegisterResponseType> register(RegisterRequestType request) async {
    if (request.isConditional)
      throw PlatformException(code: 'conditional-create-unsupported');
    if (request.prf != null)
      throw UnsupportedError('PRF is not implemented by the OHOS backend');
    final json = request.toJson();
    final result = await _channel.invokeMethod<String>('register', {
      'challenge': _bytes(request.challenge),
      'rp': json['rp'],
      'user': {...json['user'] as Map, 'id': _bytes(request.user.id)},
      'pubKeyCredParams':
          json['pubKeyCredParams'] ??
          [
            {'type': 'public-key', 'alg': -7},
            {'type': 'public-key', 'alg': -257},
          ],
      'excludeCredentials': _credentials(request.excludeCredentials),
      'timeout': request.timeout,
      'authenticatorSelection': json['authenticatorSelection'],
      'attestation': request.attestation,
    });
    return RegisterResponseType.fromJson(_response(result!));
  }

  @override
  Future<AuthenticateResponseType> authenticate(
    AuthenticateRequestType request,
  ) async {
    if (request.prf != null ||
        request.mediation == MediationType.Conditional ||
        request.mediation == MediationType.Silent ||
        request.preferImmediatelyAvailableCredentials) {
      throw UnsupportedError(
        'OHOS supports explicit, interactive passkey authentication',
      );
    }
    final result = await _channel.invokeMethod<String>('authenticate', {
      'challenge': _bytes(request.challenge),
      'rpId': request.relyingPartyId,
      'allowCredentials': _credentials(request.allowCredentials),
      'timeout': request.timeout,
      'userVerification': request.userVerification,
    });
    return AuthenticateResponseType.fromJson(_response(result!));
  }
}
