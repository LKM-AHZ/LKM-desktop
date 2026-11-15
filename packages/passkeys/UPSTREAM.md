# passkeys 2.24.1

Published source: https://pub.dev/packages/passkeys/versions/2.24.1
Archive SHA-256: `95bea8590e95a82173462a0eb6ca193c4f5d4a98981df1ee06c0029d637b3dd3`.

Original runtime API/non-OH platform dependencies retained. Removes upstream
workspace resolution for local use. Adds OH native registration in lib/passkeys.dart,
Dart method transport and a native API20+ OnlineAuthenticationKit/FIDO2 backend.
Native code is local implementation against the installed official API26 SDK;
no old incompatible passkeys interface or Android impersonation is installed.
Original package license retained.

PasskeysOhos translates current request byte fields and preserves RP IDs, allowed/
excluded credentials, algorithms, user verification and attestation preferences.
The native response JSON is converted from clientDataJson to standard clientDataJSON.
Capability probing uses real client capabilities and returns a native OH availability
subtype in the matching current interface. Unsupported devices return unavailable.
User abort/rejection maps to cancelled; device-unsupported errors remain explicit.
Only explicit interactive register/authenticate are implemented. Conditional/silent/
PRF and prefer-immediately-available flows fail rather than pretending equivalent
system behavior. The SDK exposes no cancel API; cancel on an active native sheet
reports operation_active and requires the user to dismiss it. Android-only restore/
password APIs retain their platform interface defaults. Best-effort Signal APIs keep
the interface's documented no-op fallback. Native UI/cryptographic ceremony, app/RP
association, signing certificate trust and server verification require a signed HAP
and device validation. Do not interpret mocked-SDK tests as successful authentication.
