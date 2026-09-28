// SPDX-License-Identifier: MIT
//
// Foundation for libretro core-package support: parsing of libretro core
// info (`.info`) files.
//
// `.info` files are plain-text, line-oriented manifest files shipped with
// libretro cores. A meaningful line has the shape:
//
//     key = "value"
//
// Lines beginning with `#` are comments. A trailing backslash (`\`) extends a
// logical line across the following physical line. Inside a quoted value,
// `\"` and `\\` are treated as escaped characters.
//
// This parser is deliberately lenient: malformed input produces warnings on the
// returned [RetroInfo] instead of throwing, and unknown keys are preserved so
// callers can reach them via [RetroInfo.getValue].

import 'dart:convert';

/// Parsed representation of a single libretro core info (`.info`) file.
///
/// Access the resolved key/value map through [entries], [getValue], or the
/// typed convenience getters ([name], [systemName], [systemId],
/// [supportedExtensions], [firmwareCount], [firmwareEntries]).
class RetroInfo {
  RetroInfo._();

  /// Resolved key/value pairs in first-seen order. Includes both well-known
  /// and unknown keys; nothing is discarded.
  final Map<String, String> _values = <String, String>{};

  /// All `firmware_*` key/value pairs (excluding the bare `firmware` key),
  /// kept for callers that need the raw firmware declarations.
  final Map<String, String> _firmwareEntries = <String, String>{};

  /// Non-fatal problems encountered during parsing (malformed lines,
  /// unterminated quoted values, invalid integers, etc.).
  final List<String> warnings = <String>[];

  /// Ordered, resolved key/value entries.
  List<MapEntry<String, String>> get entries =>
      List<MapEntry<String, String>>.unmodifiable(_values.entries.toList());

  /// Raw value for [key], or `null` when the key is absent.
  String? getValue(String key) => _values[key];

  /// Core name (`corename`) — the human-readable name of the core.
  String? get name => _values['corename'];

  /// Manufacturer (`manufacturer` or `manufacturers`), when declared by the
  /// core. Either spelling is accepted; the first present value wins.
  String? get manufacturer => _values['manufacturer'] ?? _values['manufacturers'];

  /// System name (`systemname`).
  String? get systemName => _values['systemname'];

  /// System id (`systemid`).
  String? get systemId => _values['systemid'];

  /// Supported file extensions (`supported_extensions`), split on `|`.
  List<String> get supportedExtensions {
    final raw = _values['supported_extensions'];
    if (raw == null || raw.isEmpty) return const <String>[];
    return raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Number of firmware entries. Prefer the declared `firmware_count` value;
  /// fall back to the number of collected `firmware_*` keys when it is absent
  /// or not a valid integer.
  int get firmwareCount {
    final declared = _values['firmware_count'];
    if (declared != null) {
      final parsed = int.tryParse(declared);
      if (parsed != null && parsed >= 0) return parsed;
    }
    return _firmwareEntries.length;
  }

  /// All `firmware_*` key/value pairs (read-only view).
  Map<String, String> get firmwareEntries =>
      Map<String, String>.unmodifiable(_firmwareEntries);

  /// Parses [input], a libretro `.info` file's text, into a [RetroInfo].
  ///
  /// Parsing never throws for malformed input; problems are collected in
  /// [warnings] and parsing continues with the best-effort interpretation of
  /// the remaining lines.
  factory RetroInfo.parse(String input) {
    final result = RetroInfo._();

    final physical = const LineSplitter().convert(input);
    final logical = <_Line>[];
    for (var i = 0; i < physical.length; i++) {
      var text = physical[i];
      final start = i + 1;
      // Trailing single backslash => line continuation (shell-like): drop the
      // backslash and append the next physical line directly.
      while (text.endsWith('\\') && _isContinuation(text) && i + 1 < physical.length) {
        text = text.substring(0, text.length - 1) + physical[i + 1];
        i++;
      }
      logical.add(_Line(text, start));
    }

    for (final line in logical) {
      final entry = _parseLine(line, result);
      if (entry == null) continue;
      final key = entry.key;
      final value = entry.value;
      if (key == 'firmware_count') {
        if (int.tryParse(value) == null) {
          result.warnings.add(
            'Line ${line.number}: firmware_count is not an integer: "$value"',
          );
        }
      }
      if (key.startsWith('firmware') && key != 'firmware_count') {
        result._firmwareEntries[key] = value;
      }
      result._values[key] = value;
    }

    return result;
  }

  /// Returns `true` when the trailing backslash is a continuation marker
  /// rather than an escaped backslash. An odd run of trailing backslashes means
  /// the last one is a continuation marker.
  static bool _isContinuation(String text) {
    var count = 0;
    var i = text.length - 1;
    while (i >= 0 && text.codeUnitAt(i) == 0x5c /* \ */) {
      count++;
      i--;
    }
    return count.isOdd;
  }

  /// Parses a single logical line into a [MapEntry], or `null` on a comment,
  /// blank, or irrecoverable line (a warning is recorded).
  static MapEntry<String, String>? _parseLine(_Line line, RetroInfo result) {
    final trimmed = line.text.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

    final eq = trimmed.indexOf('=');
    if (eq < 0) {
      result.warnings.add(
        'Line ${line.number}: expected "=" separator: "${line.text}"',
      );
      return null;
    }

    final key = trimmed.substring(0, eq).trim();
    if (key.isEmpty) {
      result.warnings.add(
        'Line ${line.number}: empty key before "=": "${line.text}"',
      );
      return null;
    }

    final rawValue = trimmed.substring(eq + 1).trim();
    final value = _parseValue(rawValue, line.number, result);
    if (value == null) return null;
    return MapEntry<String, String>(key, value);
  }

  /// Resolves a raw value token into its string form, honoring quoted values
  /// and `\"` / `\\` escapes. Returns `null` (recording a warning) for an
  /// unterminated quoted value.
  static String? _parseValue(
    String raw,
    int lineNumber,
    RetroInfo result,
  ) {
    if (raw.isEmpty) return '';
    if (!raw.startsWith('"')) return raw;

    final buffer = StringBuffer();
    var i = 1; // skip opening quote
    while (i < raw.length) {
      final ch = raw.codeUnitAt(i);
      if (ch == 0x5c /* \ */ && i + 1 < raw.length) {
        final next = raw.codeUnitAt(i + 1);
        if (next == 0x22 /* " */) {
          buffer.write('"');
          i += 2;
          continue;
        }
        if (next == 0x5c /* \ */) {
          buffer.write('\\');
          i += 2;
          continue;
        }
        // Unknown escape: preserve both characters verbatim.
        buffer.writeCharCode(ch);
        buffer.writeCharCode(next);
        i += 2;
        continue;
      }
      if (ch == 0x22 /* " */) {
        // Closing quote: warn on trailing non-whitespace, then stop.
        if (i + 1 < raw.length) {
          final rest = raw.substring(i + 1).trim();
          if (rest.isNotEmpty) {
            result.warnings.add(
              'Line $lineNumber: trailing content after closing quote: "$rest"',
            );
          }
        }
        return buffer.toString();
      }
      buffer.writeCharCode(ch);
      i++;
    }

    result.warnings.add(
      'Line $lineNumber: unterminated quoted value: "$raw"',
    );
    return null;
  }
}

/// Internal record of a logical (post-continuation) line and its 1-based
/// source line number.
class _Line {
  _Line(this.text, this.number);
  final String text;
  final int number;
}
