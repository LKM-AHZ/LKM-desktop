# file_picker 13.3.3

Base: pub.dev file_picker 13.3.3, archive SHA-256 `079dc46b753abbddb7f77cd87e6ed9ecc62902580707514568321bdf8e050a86`
(fetched from the pub.flutter-io.cn mirror).
The current public wrapper and existing platform dependencies are retained.

OHOS backend: https://gitcode.com/oh-flutter/file_picker
Commit: `a845c22b0c444d1724f1d6be9600b5795358c327` (13.1.0-ohos.2).
Only the OHOS backend and native directory are ported to this same package.

Local corrections: cache selected provider files
for Dart IO, handle selection status/cancellation, close descriptors and honor
byte views/partial writes when saving. Provider directory URIs cannot be
returned as absolute filesystem paths; this capability reports UnsupportedError.

Local package metadata: `publish_to: none`, `resolution: workspace` and upstream dev
dependencies removed, `ohos` plugin platform registered, `src/file_picker_ohos.dart`
exported from `lib/file_picker.dart`.
