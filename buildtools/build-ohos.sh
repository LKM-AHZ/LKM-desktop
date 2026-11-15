#!/usr/bin/env bash
# Linux host build, using the same app/dependency graph as every other target.
set -euo pipefail
cd "$(dirname "$0")/.."
source buildtools/env-ohos.sh
export PATH="/usr/bin:$PATH"
bash buildtools/patch-ohos-sdk.sh
flutter pub get
python3 buildtools/prepare-ohos-media.py
flutter build hap --no-pub --no-codesign --target-platform ohos-arm64 "$@"
if [[ " $* " == *" --debug "* ]]; then
    python3 buildtools/verify-ohos-hap.py
else
    python3 buildtools/verify-ohos-hap.py --require-aot
fi
