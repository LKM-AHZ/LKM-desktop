# flutter_nfc_kit 3.7.0

Published source: https://pub.dev/packages/flutter_nfc_kit/versions/3.7.0
Archive SHA-256: `aaf11749318e7e5cf8c54eb6c3ee02685ccc7021efd3cf467a5f106cdc752a66`.

Native community source: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_nfc_kit.git
Fixed commit: `2d0251fc83e27ef22e414c70677257a8dc5882a0`; inspected branch `br_3.41_dev`.

Current Dart and all original platforms remain. OHOS tagStream is enabled;
real community native backend handles availability, foreground readerMode poll,
NDEF, transceive and MIFARE. Synchronous SDK failures now settle the pending
method result instead of hanging. Requires NFC_TAG permission (SDK 26), not
NFC_CONTROLLER; no radio toggle API is used. Foreground poll is the application
path. Background Want dispatch is not wired or claimed. Hardware/tag/technology
compatibility remains a device acceptance requirement.

Existing licenses retained; additional native Apache license is bundled via
Flutter licenses. Examples/tests/build caches omitted.
