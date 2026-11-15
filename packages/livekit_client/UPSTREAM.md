# livekit_client 2.13.2

Published baseline: https://pub.dev/packages/livekit_client/versions/2.13.2
Archive SHA-256: `c63211bd5073b308417de2b048809c156f50cb5bda02713150478742be2a1bc1`.
Native OHOS source: https://gitcode.com/CPF-Flutter/fluttertpc_livekit_client
Fixed commit: `61566610f29298c819caadc0f69ee3686119f95b`.

Current public Dart API and original platform sources/dependencies are retained.
Single shared override, no old WebRTC/LiveKit dependency downgrade. Current
platform detection adds OHOS mobile and LiveKit ClientInfo OS; original targets
retain their behavior. Existing examples/tests are omitted, licenses retained.
Additional native copyright notices are included through flutter.licenses.

OHOS WebRTC binary is fetched/prepared by buildtools/prepare-ohos-media.py,
11,091,832 bytes, SHA-256
`39f42ab2d86bdafad47102b80e69f0f0adb49b66061a9f7931b6cd5d00510ad4`.
It is real ARM64 OHOS ELF, not the 133-byte Git LFS pointer; generated files
stay out of Git. Linux preparation checks both length and hash.

Native RTC fixes include permission refusal/async failure completion, checking
all requested permissions (not just the first), not asking camera for video=false,
current texture-only renderer protocol, native surface registration/resizing/
unregistration, keeping shared tracks alive on renderer detach, and honoring ICE
relay/bundle/mux/pool configuration. Upstream unconditional AEC audio debug dump
is removed. Optional unimplemented local-stream creation, native record/snapshot,
explicit input selection and frame/data cryptors return errors, never hang or
return a fake key-provider ID. LiveKit explicitly reports media E2EE unsupported.
No capability is manufactured for the old binary's missing FrameCryptor API.

The LiveKit extra native plugin contains no implemented platform-specific audio
capture/visualizer/session features; its unsupported methods remain unavailable.
The app's current call path uses flutter_webrtc ordinary media tracks; that
native transport is included, but real peers/ICE/TURN, hardware camera/audio
routing, lifecycle and remote rendering are NOT device-accepted by a HAP build
or mocked SDK tests. Never claim this makes all public SDK APIs supported.

Speaker routing on OHOS goes through the actual WebRTC AudioRoutingManager,
awaits completion and propagates failure; LiveKit speaker preference no longer
only changes its Dart state. A renderer owns its native texture, not its shared
MediaStreamTrack; late event subscribers receive cached real frame dimensions.
