# mobile_scanner 7.5.0

Published source: https://pub.dev/packages/mobile_scanner/versions/7.5.0
Archive SHA-256: `175c62fc813c2bd762757359a2088f8cbdb72020cf85d4cd27fc4d3fe59be058`.

Native community source: https://gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner.git
Fixed commit: `f5a4ff52f003e1645db1d4de743a2db0313665a8`; inspected branch `br_v7.4.2_ohos_dev`.

Current Dart and original platforms remain. Adds the existing ScanKit/camera
backend; OHOS participates in barcode parsing. Integral native geometry converts
with num.toDouble; the old epsilon-padding workaround is removed. Native errors
from async start/pause/stop/analyze now propagate; start exceptions clean up;
detach stops capture before unregistering its texture; SDK decoder failures
notify BarcodeError. Rear capture keeps ScanKit customScan. Front and external
(USB/remote connection type) capture now select a real CameraKit CameraDevice,
configure a PhotoSession with preview + ImageReceiver outputs, and decode the
actual NV21 frames with ScanKit detectBarcode.decodeImage. Per-frame row stride
is removed before decoding; preview rotation is applied to barcode coordinates
and optional returned JPEGs. Camera count comes from getSupportedCameras; absent
cameras, incompatible output profiles, unsupported torch/focus/zoom and SDK errors
are not reported as successful capture. Selected-camera inversion remains an
explicit error; optional lens enumeration remains unsupported. Selected-camera
pause/stop/detach closes the session/outputs/input/receiver, waits for in-flight
frames, and handles detachment while the input is opening. Returned image source,
pixel maps and packer are released after packing. Shared noDuplicates mode filters
repeated values; hardware permission, dual-output availability, external camera
pixel layout, front mirroring/orientation and sustained decoding require a device.

SDK evidence: `@hms.core.scan.customScan.d.ts` ViewControl has width/height/surfaceId
but no camera selector; `@ohos.multimedia.camera.d.ts` exposes front position,
USB/remote ConnectionType, preview profiles and canAddOutput;
`@hms.core.scan.detectBarcode.d.ts` ByteImage accepts NV21 and returns DetectResult.
ImageReceiver is constructed with nominal JPEG format and its JPEG component
contains the actual preview producer's bytes, as documented by the SDK's
`@ohos.multimedia.image.d.ts` Image/Component APIs. The selected profile is
CAMERA_FORMAT_YUV_420_SP (NV21); unknown or short buffer layouts fail explicitly.
`node buildtools/verify-ohos-device-plugins.mjs` loads the real ArkTS modules and
checks camera selection, dual-output/stride decoding, native channel replies,
unsupported hardware controls and detachment during open. It also checks the
installed SDK's declarations; these stubs do not establish hardware support.

Existing licenses retained; additional native Apache license is bundled via
Flutter licenses. Examples/tests/build caches omitted.
