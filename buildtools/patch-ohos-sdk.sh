#!/usr/bin/env bash
# Apply the local patches the OH-Flutter SDK needs for this project.
set -euo pipefail

lkm_patches_dir="$(cd "$(dirname "$0")" && pwd)/patches"
# flutter-ohos-native-assets: preserve the OHOS target for application hooks.
# flutter-ohos-desktop-dart-artifacts: resolve Dart SDK tools as host artifacts
# on desktop targets (upstream lookups went through the macOS framework path).
lkm_patches=(
    flutter-ohos-native-assets.patch
    flutter-ohos-desktop-dart-artifacts.patch
)
if [ "$#" -gt 0 ]; then
    lkm_flutter_root="$1"
else
    lkm_flutter_bin="$(readlink -f "$(command -v flutter)")"
    lkm_flutter_root="$(dirname "$(dirname "$lkm_flutter_bin")")"
fi

lkm_applied=false
for lkm_name in "${lkm_patches[@]}"; do
    lkm_patch="$lkm_patches_dir/$lkm_name"
    if git -C "$lkm_flutter_root" apply --reverse --check "$lkm_patch" 2>/dev/null; then
        echo "SDK patch already applied: $lkm_name"
    elif git -C "$lkm_flutter_root" apply --check "$lkm_patch"; then
        git -C "$lkm_flutter_root" apply "$lkm_patch"
        lkm_applied=true
        echo "Applied SDK patch: $lkm_name"
    else
        echo "SDK does not match the recorded OH-Flutter patch $lkm_name: $lkm_flutter_root" >&2
        exit 1
    fi
done

if [ "$lkm_applied" = true ]; then
    # Force the normal Flutter bootstrap to rebuild its tool snapshot.
    rm -f "$lkm_flutter_root/bin/cache/flutter_tools.stamp"
    echo "Flutter will rebuild its tool on the next invocation."
fi
