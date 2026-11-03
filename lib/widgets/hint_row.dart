import 'package:flutter/material.dart';

import '../state/input_mode.dart';
import '../theme/tokens.dart';

/// One hint: the glyph chip and what it does here (§7.4).
class OrbitHint {
  const OrbitHint(this.glyph, this.label);

  final String glyph;
  final String label;
}

/// The hint row along the bottom edge, right aligned.
///
/// The shell renders it; each layer supplies its own list. Glyphs come from
/// the last input used, so the row switches keyboard ↔ pad in one event.
class HintRow extends StatelessWidget {
  const HintRow({super.key, required this.hints});

  final List<OrbitHint> hints;

  @override
  Widget build(BuildContext context) {
    if (hints.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Hints',
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, hint) in hints.indexed) ...[
              if (i > 0) const SizedBox(width: 24),
              _Hint(hint: hint),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.hint});

  final OrbitHint hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0x1ADDE6F4), // rgba(221,230,244,.1)
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x2BFFFFFF)), // .17
          ),
          child: Text(
            hint.glyph,
            maxLines: 1,
            style: Tokens.glyphChip.copyWith(color: Tokens.text),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          hint.label,
          style: Tokens.body(
            size: 14,
            weight: FontWeight.w600,
            color: Tokens.muted,
            height: null,
          ),
        ),
      ],
    );
  }
}

/// The hints for a shell layer, in the glyph set of the last input used.
///
/// Mirrors the prototype's per-layer lists (§4.3). A screen that later needs
/// its own row can pass a list straight to [HintRow].
List<OrbitHint> hintsForPage(
  String page,
  GlyphSet glyphs, {
  String libraryConfirm = 'Play',
}) {
  switch (page) {
    case 'library':
      return [
        OrbitHint(glyphs[GlyphKey.confirm], libraryConfirm),
        OrbitHint(glyphs[GlyphKey.details], 'Details'),
        OrbitHint(glyphs[GlyphKey.options], 'Options'),
        OrbitHint(glyphs.tab, 'System'),
        OrbitHint(glyphs[GlyphKey.view], 'Look'),
      ];
    case 'cores':
      return [
        OrbitHint(glyphs[GlyphKey.confirm], 'Show games'),
        OrbitHint(glyphs[GlyphKey.options], 'Remove'),
        OrbitHint(glyphs.tab, 'Tab'),
        OrbitHint(glyphs[GlyphKey.back], 'Library'),
      ];
    case 'capsule':
      return [
        OrbitHint(glyphs[GlyphKey.confirm], 'Options'),
        OrbitHint(glyphs[GlyphKey.options], 'Delete'),
        OrbitHint(glyphs[GlyphKey.back], 'Library'),
      ];
    case 'settings':
      return [
        OrbitHint(glyphs[GlyphKey.confirm], 'Change'),
        OrbitHint(glyphs.tab, 'Section'),
        OrbitHint(glyphs[GlyphKey.back], 'Library'),
      ];
    default:
      return const [];
  }
}
