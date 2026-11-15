import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// Binds the shared authentication surfaces to the host app's client and alert
/// surface.
///
/// The elevation flow never reaches into app state directly: the host owns the
/// authenticated client and how an error is shown, exactly the way the drive
/// takes its client, secret store and task sink through overrides.

/// Authenticated Solar Network client (the host owns auth and construction).
///
/// Only `client.auth` is used today — the elevation challenge — but the seam
/// takes the whole client because the host already builds one for the rest of
/// the app.
final authClientProvider = Provider<SolarNetworkClient>(
  (ref) => throw UnimplementedError(
    'authClientProvider must be overridden by the host app',
  ),
);

/// Surfaces an error to the user (alert, dialog or toast).
typedef AuthErrorReporter = void Function(Object error);

/// Error reporter used when the elevation flow fails.
///
/// Defaults to a no-op so a headless host — or a test — can omit it.
final authErrorReporterProvider = Provider<AuthErrorReporter>(
  (ref) => (error) {},
);

/// Runs the WebAuthn assertion ceremony a host uses to settle a step-up
/// challenge with a registered passkey.
///
/// Stargate settles passkey assertions through the challenge's dedicated
/// endpoints (`POST /auth/challenge/{id}/passkey/start` and `.../complete`),
/// never through the picker's code step, so the shared elevation sheet cannot
/// run the ceremony itself: the WebAuthn plugin is a host dependency and the
/// host owns the client the assertion is registered against.
class AuthPasskeyCeremony {
  /// Whether this device can present a passkey right now. The sheet asks
  /// first, because availability is a platform query (biometry, a security
  /// key, browser support).
  final Future<bool> Function() isAvailable;

  /// Runs the assertion for [challenge] and returns the challenge the server
  /// answered with. Throws on cancel or failure; the sheet reports it through
  /// [authErrorReporterProvider].
  final Future<SnAuthChallenge> Function(SnAuthChallenge challenge) run;

  const AuthPasskeyCeremony({required this.isAvailable, required this.run});
}

/// Host-supplied passkey ceremony for the elevation sheet.
///
/// Defaults to null: a host that cannot run WebAuthn on this target never
/// offers the button.
final authPasskeyCeremonyProvider = Provider<AuthPasskeyCeremony?>(
  (ref) => null,
);
