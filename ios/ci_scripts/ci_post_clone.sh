#!/bin/sh
# Xcode Cloud runs this right after cloning, before it resolves packages and archives ios/Runner.xcworkspace.
# A clean Xcode Cloud machine has no Flutter SDK, no Generated.xcconfig and no Pods: this provides all three.
# Ship a TestFlight build:  git push -f origin HEAD:testflight
set -e

# Same Flutter as the local release builds; bump it here when you upgrade locally.
FLUTTER_VERSION=3.47.9

git clone https://github.com/flutter/flutter.git --depth 1 --branch "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter precache --ios
flutter pub get

HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
cd ios && pod install

exit 0
