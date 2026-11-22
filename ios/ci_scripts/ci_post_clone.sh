#!/bin/sh
# Xcode Cloud runs this right after cloning, before it resolves packages and archives ios/Runner.xcworkspace.
# A clean Xcode Cloud machine has no Flutter SDK, no Generated.xcconfig and no Pods: this provides all three.
# Ship a TestFlight build: Start Build on the branch in the Xcode Cloud workflow (App Store Connect or Xcode).
set -e

# CocoaPods' Ruby crashes on a non-UTF-8 locale.
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Same Flutter as the local release builds; bump toolchain.json when upgrading.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
FLUTTER_VERSION="$(python3 "$REPO_ROOT/scripts/toolchain_pin.py" get flutter)"

git clone https://github.com/flutter/flutter.git --depth 1 --branch "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

# Local release builds run with Swift Package Manager off, so every plugin comes from CocoaPods.
# A fresh Flutter defaults it on, which moves plugins out of the Podfile and breaks the build.
flutter config --no-enable-swift-package-manager

cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter precache --ios
flutter pub get

HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
cd ios && pod install

exit 0
