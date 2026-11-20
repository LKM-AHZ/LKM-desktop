#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory is ios/ci_scripts/. Move to the repository root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "=== Installing Flutter SDK ==="
# Vendored plugins share OHOS platform cases on every target, so Xcode Cloud
# must use the same OH-Flutter release as local development.
FLUTTER_VERSION=$(tr -d '\r\n' < .flutter-version)
if [ -z "$FLUTTER_VERSION" ]; then
  echo "Could not read the Flutter version from .flutter-version"
  exit 1
fi
echo "Pinned Flutter version: $FLUTTER_VERSION"
git clone https://atomgit.com/oh-flutter/flutter_flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter --version

# Pre-cache iOS artifacts and fetch dependencies
flutter precache --ios
flutter pub get

echo "=== Installing CocoaPods ==="
# Disable homebrew auto-updates to save CI time
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

# Install iOS pods
echo "=== Running Pod Install ==="
cd ios
pod install --repo-update

# Return to root and generate configurations
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter build ios --config-only

echo "=== Script finished successfully ==="
exit 0
