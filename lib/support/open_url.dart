// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

/// The store's own subscription-management page for this platform.
String manageSubscriptionsUrl() => Platform.isAndroid
    ? 'https://play.google.com/store/account/subscriptions'
    : 'https://apps.apple.com/account/subscriptions';

/// Opens a support link in the device browser. The Sponsors card is only shown
/// on builds without a store (desktop), so the desktop opener is all that is
/// needed; store builds never call this.
Future<void> openSupportUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  } catch (_) {
    // A missing browser must never break the settings screen.
  }
}
