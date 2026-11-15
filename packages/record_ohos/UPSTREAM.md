# record_ohos 1.0.0, forward port to record 7

Source: https://gitcode.com/CPF-Flutter/fluttertpc_record
Branch at inspection: `br_v6.1.2_ohos`
Fixed commit: `c719424e0cd869bf57198e71768d11f995cce849`.

Based on the Apache-2.0 native plugin/channel and AVRecorder integration from
`record_ohos`. Retains the upstream LICENSE and index/build metadata; native
files carry their original Huawei Apache copyright. LICENSE-OHOS contains the
Apache license and is declared in Flutter's additional licenses. The old source
was for record 6/interface 1; the current shared package stays record 7.1.2 and
interface 2.1.0. No old interface override is installed.

Replaced the old asynchronous wrapper: start/pause/resume/stop/dispose now await
SDK work and return failures. Encoders are not silently changed to AAC. AAC-LC
files use AVRecorder/M4A; PCM16 raw files, PCM16 streams and WAV files use
AudioCapturer S16LE. WAV headers are finalized at stop; file writes handle partial
progress and FDs/resources are closed. Samples are converted to dBFS. Event
channels use the current state ordering and Uint8List/end-of-stream protocol;
the bounded 1 MiB start/listen buffer avoids losing initial data. Permission
check-only never prompts; explicit `hasPermission()` requests the microphone.
Detach cancels active capture and cleans per-recorder channels.

The Dart registrar reuses current interface transport (an intentional internal
import, as it is not publicly exported); `cancel` awaits native cleanup (the
interface mixin drops the Future), and `getAmplitude` converts numbers to double
because the OHOS standard codec encodes integral JavaScript numbers such as
silence -160 or full-scale 0 as Dart ints. All platforms still use one main
package and pubspec. OHOS has no app-code fork.

Supported: AAC-LC to M4A, PCM16 raw file/stream, WAV PCM16 file, mono/stereo,
exact requested sample format/rate, pause/resume, cancel, dBFS amplitude. Other
encoders, encoded/WAV streams, and explicit input-device selection fail instead
of pretending success; the mobile input list is empty. SDK/device limitations
are returned as errors, not silent configuration changes. Optional gain/echo/
noise flags, Android/iOS-specific options and streamBufferSize are not guaranteed
by this backend; config-change callbacks remain available through current Dart
transport, but no format substitution is performed.

Foreground recording only: no continuous background task, automatic interruption
resume, or background-recording permission is added. Forced PCM interruption and
asynchronous recording/write errors notify the state stream and finalize a
recoverable prefix (stop returns it; cancel removes it). Real microphone/audio
routing, AAC codec availability, lifecycle timing and sustained throughput need
device validation; SDK-boundary regressions and a HAP build are not acceptance.
