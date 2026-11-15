# media_kit_libs_video 1.0.7

Published baseline: https://pub.dev/packages/media_kit_libs_video/versions/1.0.7
Archive SHA-256: `2b235b5dac79c6020e01eef5022c6cc85fedc0df1738aadc6ea489daa12a92a9`.

OHOS source: CPF-Flutter/fluttertpc_flutter_media_kit commit
`d424290ea300c140a1f563f44a8f0461628a3aa4`. Current Dart API and every
original platform backend/dependency are retained; examples/tests/screenshots
are omitted. OHOS uses the same native MPV runtime (1.2.6 API), and a new
texture transport (2.0.1 API), not the older fork's Dart facade.

All targets use one pubspec. The native package requires the reproducible
`python3 buildtools/prepare-ohos-media.py` step before building. No engine
libc++ copy is vendored; the app already packages the matching shared runtime.

Flutter assets on OHOS are extracted asynchronously through rootBundle before
open/add/external audio/subtitle operations; bytes use the exact ByteData view.
Memory playlists and temporary files use Directory.systemTemp, configured to
the app cache by FlutterLoader. Other platform source paths keep existing behavior.

OHOS texture creation returns actual texture and surface IDs, validates sizes,
propagates registry errors and uses unregisterTexture (the SDK entry.release
method is unimplemented). It does not reset playback position on resize.
The first-frame-rendered callback is explicitly unsupported because the current
SDK exposes no frame-consumed callback. Hot restart, real decoder/video/audio
output, surface teardown and device routes require device validation.
