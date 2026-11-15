# media_kit_video 2.0.1

Published baseline: https://pub.dev/packages/media_kit_video/versions/2.0.1
Archive SHA-256: `afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d`.

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

Verified against the resolved OH-Flutter HAR's `src/main/ets/view/TextureRegistry.ets`
and `embedding/engine/renderer/FlutterRenderer.ets`: a standalone
OnFrameConsumedListener interface exists, but SurfaceTextureEntry/TextureRegistry
expose no listener registration and FlutterRenderer never calls it. The native
OH_NativeImage_SetOnFrameAvailableListener signals producer frame availability,
not Flutter frame consumption, and cannot certify this getter. No texture create,
size event, MPV playback property or first decoded frame is treated as consumption.
`node buildtools/verify-ohos-media.mjs` prefers the app's resolved embedding package
and checks this exact boundary so a future SDK capability can be detected.
