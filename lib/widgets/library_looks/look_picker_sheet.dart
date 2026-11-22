// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter/material.dart';

import '../../theme/symbols.dart';
import '../../theme/tokens.dart';
import '../library_header.dart' show LibraryLook;

/// The phone's Library look picker (Devices 4b). Each row shows a miniature of
/// the look, not just its name — the same five cards are used on first run and
/// in Settings → Appearance. The sheet holds exactly the five looks: sorting
/// lives in the header's view control, not here.
Future<LibraryLook?> showLookPickerSheet(
  BuildContext context, {
  required LibraryLook value,
}) => showModalBottomSheet<LibraryLook>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (context) => LookPickerSheet(value: value),
);

class LookPickerSheet extends StatelessWidget {
  const LookPickerSheet({super.key, required this.value});

  final LibraryLook value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: Tokens.sheetDecor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Tokens.lineStrong,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Library look',
            style: Tokens.display(size: 22, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Same games, five ways to browse.',
            style: Tokens.body(size: 14, color: Tokens.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          for (final look in LibraryLook.values) ...[
            _LookRow(look: look, selected: look == value),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _LookRow extends StatelessWidget {
  const _LookRow({required this.look, required this.selected});

  final LibraryLook look;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${look.label} view',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(look),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 62,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected ? const Color(0x14007BFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Tokens.accentHi : Tokens.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _LookPreview(look: look),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        look.label,
                        style: Tokens.body(
                          size: 15,
                          weight: FontWeight.w700,
                          color: selected ? Tokens.text : Tokens.muted,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        lookSubtitle(look),
                        style: Tokens.body(
                          size: 12,
                          color: Tokens.muted,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Symbols.checkCircle,
                    size: 20,
                    color: Tokens.accentHi,
                    fill: 1,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String lookSubtitle(LibraryLook look) => switch (look) {
  LibraryLook.flow => 'Covers turn in space',
  LibraryLook.shelf => 'Rows by what you play',
  LibraryLook.wall => 'A curved wall of covers',
  LibraryLook.grid => 'Every cover at a glance',
  LibraryLook.list => 'Titles and details',
};

/// A 40×40 miniature of the look's arrangement: a few cards in the shape the
/// real look uses. It is a UI preview, not game art.
class _LookPreview extends StatelessWidget {
  const _LookPreview({required this.look});

  final LibraryLook look;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF111C29),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: switch (look) {
        LibraryLook.flow => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(6, 15, 0.5),
            _bar(12, 24, 1),
            _bar(6, 15, 0.5),
          ],
        ),
        LibraryLook.shelf => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (var i = 0; i < 3; i++) _row(3)],
        ),
        LibraryLook.wall => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (var i = 0; i < 2; i++) _row(5)],
        ),
        LibraryLook.grid => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (var i = 0; i < 3; i++) _row(6)],
        ),
        LibraryLook.list => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (var i = 0; i < 3; i++) _row(4)],
        ),
      },
    );
  }

  Widget _bar(double w, double h, double op) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Tokens.accentHi.withValues(alpha: op),
      borderRadius: BorderRadius.circular(1),
    ),
  );

  Widget _row(int count) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (var i = 0; i < count; i++)
        Container(
          width: 3,
          height: 5,
          decoration: BoxDecoration(
            color: i == 0 ? Tokens.accentHi : Tokens.muted,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
    ],
  );
}
