import 'dart:convert';
import 'dart:io';

import 'sha256.dart' as pure;

/// Computes SHA-256 hashes of file contents.
///
/// Abstracted so tests can inject deterministic behavior independent of
/// platform hashing tools.
abstract class HashVerifier {
  Future<String> sha256File(String path);
}

/// Verifies [path] against the lowercase hex [pin], using a sidecar fast
/// path: `<path>.ezpin` records `{pin, size, mtimeMs}` from the last full
/// verification. Unchanged files skip re-hashing (matters on mobile where
/// hashing is pure-Dart); any size/mtime/pin difference re-hashes fully.
/// The vault is app-private, so sidecar trust is sound: tampering with the
/// vault already implies device compromise, and every mismatch deletes.
Future<bool> verifyPinnedFile(
  String path,
  String pin, {
  HashVerifier? hashes,
}) async {
  final want = pin.toLowerCase();
  final file = File(path);
  if (!file.existsSync()) return false;
  final stat = file.statSync();
  final sidecar = File('$path.ezpin');
  if (sidecar.existsSync()) {
    try {
      final record =
          json.decode(sidecar.readAsStringSync()) as Map<String, dynamic>;
      if ((record['pin'] as String?)?.toLowerCase() == want &&
          record['size'] == stat.size &&
          record['mtimeMs'] == stat.modified.millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {
      // Corrupt sidecar: fall through to a full verification.
    }
  }
  final verifier = hashes ?? const PlatformHashVerifier();
  String actual;
  try {
    actual = (await verifier.sha256File(path)).toLowerCase();
  } catch (_) {
    return false;
  }
  if (actual != want) {
    try {
      sidecar.deleteSync();
    } catch (_) {}
    return false;
  }
  try {
    sidecar.writeAsStringSync(
      json.encode({
        'pin': want,
        'size': stat.size,
        'mtimeMs': stat.modified.millisecondsSinceEpoch,
      }),
    );
  } catch (_) {
    // Sidecar is a pure optimization; verification already succeeded.
  }
  return true;
}

/// Pure-Dart hashing. Works on every platform including iOS/Android,
/// where `Process` is unavailable. Used directly on mobile and as the
/// fallback below on desktop.
class DartHashVerifier implements HashVerifier {
  const DartHashVerifier();

  @override
  Future<String> sha256File(String path) => pure.sha256File(path);
}

/// Production verifier: native shell tools first for speed (`shasum` on
/// macOS, `sha256sum` on Linux, `certutil` on Windows), pure-Dart fallback
/// when no tool exists or `Process` is unsupported (mobile).
class PlatformHashVerifier implements HashVerifier {
  const PlatformHashVerifier();

  @override
  Future<String> sha256File(String path) async {
    final candidates = [
      ['shasum', '-a', '256', path],
      ['sha256sum', path],
      ['certutil', '-hashfile', path, 'SHA256'],
    ];
    for (final cmd in candidates) {
      try {
        final result = await Process.run(cmd.first, cmd.skip(1).toList());
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final tokens = output.split(RegExp(r'\s'));
          for (final token in tokens) {
            final cleaned = token.trim();
            if (cleaned.length == 64 &&
                RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) {
              return cleaned;
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
    try {
      return await const DartHashVerifier().sha256File(path);
    } catch (_) {
      throw StateError('No SHA-256 tool available on this platform');
    }
  }
}
