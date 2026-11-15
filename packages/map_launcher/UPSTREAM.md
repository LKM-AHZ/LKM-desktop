# map_launcher 7.0.0

Published source: https://pub.dev/packages/map_launcher/versions/7.0.0
Archive SHA-256: `5201a3d76aee07df0a5b0db99e89e55a8cadadffc02e1bd4d132032e066ad1b5`.

Native community source: https://gitcode.com/CPF-Flutter/fluttertpc_map_launcher.git
Fixed commit: `502bc8354801f9e85222dccec06aa11717873dc8`; inspected branch `br_4.4.2_ohos`.

Current public Dart API/URL builders and original platforms remain. The old
4.x native protocol is replaced with current launch/probe methods; startup
requires an Ability, waits for startAbility, and distinguishes confirmed resolver
rejection from unknown errors so fallback is safe. Android package names are not
used as OHOS bundle names. OHOS retains platform=null (universal URLs), probes
provided map URL schemes, and avoids treating Apple Maps as always installed.
Map-specific iOS/Android schemes are not promised to work on HarmonyOS; apps
without universal URLs (e.g. current Petal model) remain unavailable. Probe
schemes require host querySchemes; actual app-link handoff needs device tests.

Existing licenses retained; additional native Apache license is bundled via
Flutter licenses. Examples/tests/build caches omitted.
