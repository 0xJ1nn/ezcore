/// Small display helpers shared by the library dock, tiles, and cards.
///
/// These are presentation only — no logic depends on the strings, and no
/// value is invented: every formatter takes a value the app already
/// tracks and renders it honestly, or says it isn't known yet.
library;

/// "Never" / "Just now" / "2 days ago" / "12 Mar 2026" for a stored
/// epoch-millis stamp. A zero stamp means "never played", not "epoch".
String lastPlayedLabel(int epochMs) {
  if (epochMs <= 0) return 'Never played';
  final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final diff = DateTime.now().difference(then);
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 365) {
    return '${(diff.inDays / 7).floor()} wk ago';
  }
  final mm = then.month.toString().padLeft(2, '0');
  final dd = then.day.toString().padLeft(2, '0');
  return '${then.year}-$mm-$dd';
}

/// Byte count as a short, honest label.
String fileSizeLabel(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Count label that pluralises honestly: 1 state / 0 states / 12 states.
String countLabel(int n, String singular, [String? plural]) =>
    n == 1 ? '1 $singular' : '$n ${plural ?? '${singular}s'}';
