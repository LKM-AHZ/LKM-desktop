# OHOS MPV runtime

Source: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_media_kit
Fixed commit: `d424290ea300c140a1f563f44a8f0461628a3aa4`.
Upstream original OHOS package license was an unfilled template, preserved as
LICENSE-UPSTREAM-TEMPLATE. LICENSE is the parent repository's MIT wrapper license;
it does not replace the native components' licenses. GPL/LGPL license texts are
packaged as additional notices.

Native source path: libs/ohos/media_kit_libs_ohos_video/ohos/libs/arm64-v8a/libmpv.so.2
SHA-256: `45febf6194b02561572b98659e5c13b672bf86503dd4835688a284326ba18811`
Size: 97819184. Published OHOS clang 15.0.4 binary, MPV v0.40.0. The pinned
repository's tpc_c_cplusplus/thirdparty contains build recipes and OpenHarmony
patches, including MPV 0.40.0 and FFmpeg n6.1; these are the corresponding source
locations, not a claim that this binary was locally rebuilt. The artifact embeds
FFmpeg LGPL-2.1-or-later components. Distribution still needs complete native
component notices/source obligations checked; this work is unsigned local validation.

The reproducible preparation script verifies source commit, full bytes and hash,
then generates libmpv.so (the filename used by the Dart loader); the ELF SONAME
remains libmpv.so.2. No other library links against the filename. Actual 24 MPV
C functions invoked by current media_kit 1.2.6 are exported. Four deprecated lazy
FFI declarations (mpv_detach_destroy, mpv_get_sub_api, mpv_resume, mpv_suspend) are
not exported by MPV 0.40 but are not invoked by the package's runtime.

Do not copy the old libc++_shared.so: the app's engine/SDK supplies its shared
runtime. All ELF dependencies are available in API26 NDK; no GNU/Linux libraries.
