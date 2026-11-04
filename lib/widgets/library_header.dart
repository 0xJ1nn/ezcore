import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/system_labels.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// The five library looks (§8.1): 3D shelf is the default, then Shelf, Wall,
/// Grid and List.
///
/// Kept separate from [CollectionView] (which the Systems screen still uses
/// for its three views) so the library can grow two looks without changing
/// another screen's saved preference. The setting is still `libraryViewKey`,
/// and every old value ('3d', 'grid', 'list') reads back unchanged.
enum LibraryLook {
  flow('3d', '3D shelf', Symbols.viewCarousel),
  shelf('shelf', 'Shelf', Symbols.viewAgenda),
  wall('wall', 'Wall', Symbols.panoramaHorizontal),
  grid('grid', 'Grid', Symbols.gridView),
  list('list', 'List', Symbols.viewList);

  const LibraryLook(this.value, this.label, this.icon);

  /// The value stored in settings.
  final String value;
  final String label;
  final IconData icon;

  static LibraryLook fromSetting(Object? raw) {
    for (final v in values) {
      if (v.value == raw) return v;
    }
    return flow;
  }

  /// The next look when the View key or the V chip cycles them.
  LibraryLook get next => values[(index + 1) % values.length];
}

/// One chip in the library's filter row: a system, All games or Favorites.
class LibraryFilterChip {
  const LibraryFilterChip({
    required this.id,
    required this.label,
    required this.count,
  });

  final String id;
  final String label;
  final int count;
}

/// The library's search field: 240×46, r23, with the `/` glyph chip (§8.1).
///
/// Focus is owned by the caller so the `/` shortcut, the header field and the
/// phone search button all move the same focus.
class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.width = 240,
    this.height = 46,
    this.hint = 'Find a game',
    this.showShortcut = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final double width;
  final double height;
  final String hint;
  final bool showShortcut;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final radius = BorderRadius.circular(height / 2);
          return AnimatedContainer(
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            padding: EdgeInsets.only(left: height * 0.3, right: height * 0.24),
            decoration: BoxDecoration(
              color: const Color(0x8C060A11), // rgba(6,10,17,.55)
              borderRadius: radius,
              border: Border.all(
                color: focused
                    ? Tokens.accent.withValues(alpha: 0.7)
                    : const Color(0x1FDDE6F4),
                width: focused ? 1.5 : 1,
              ),
              boxShadow: focused
                  ? const [BoxShadow(color: Color(0x2E007BFF), blurRadius: 14)]
                  : null,
            ),
            child: Row(
              children: [
                const Icon(Symbols.search, size: 18, color: Tokens.muted),
                SizedBox(width: height * 0.2),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    onChanged: onChanged,
                    style: Tokens.body(size: 14, color: Tokens.text),
                    cursorColor: Tokens.accent,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: Tokens.body(
                        size: 14,
                        color: Tokens.muted,
                        height: null,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (showShortcut) const _SlashChip(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SlashChip extends StatelessWidget {
  const _SlashChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x1ADDE6F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x2BFFFFFF)),
      ),
      child: Text(
        '/',
        style: Tokens.glyphChip.copyWith(color: Tokens.text, fontSize: 11),
      ),
    );
  }
}

/// The 3D shelf / Shelf / Wall / Grid / List switcher: a segmented pill where
/// the active look shows its label and the rest are icons (§8.1).
class LibraryLookSwitch extends StatelessWidget {
  const LibraryLookSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 46,
    this.iconOnly = false,
  });

  final LibraryLook value;
  final ValueChanged<LibraryLook> onChanged;

  /// 46 on desktop, 38 on phones (inside the compact tool row).
  final double height;

  /// Phones: no labels at all, so the five looks stay in one short row.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final itemHeight = height - 8;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x8C060A11), // rgba(6,10,17,.55)
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1FDDE6F4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final look in LibraryLook.values) ...[
            const SizedBox(width: 2),
            _LookButton(
              look: look,
              active: look == value,
              height: itemHeight,
              iconOnly: iconOnly,
              onTap: () => onChanged(look),
            ),
          ],
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _LookButton extends StatelessWidget {
  const _LookButton({
    required this.look,
    required this.active,
    required this.height,
    required this.iconOnly,
    required this.onTap,
  });

  final LibraryLook look;
  final bool active;
  final double height;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      look.label,
      maxLines: 1,
      style: Tokens.body(
        size: 13.5,
        weight: FontWeight.w700,
        color: Colors.white,
        height: null,
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      label: '${look.label} view',
      child: Tooltip(
        message: look.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              height: height,
              constraints: const BoxConstraints(minWidth: 42),
              padding: EdgeInsets.symmetric(
                horizontal: active && !iconOnly ? 14 : 0,
              ),
              decoration: BoxDecoration(
                color: active ? const Color(0x38007BFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? const Color(0x8C007BFF) : Colors.transparent,
                ),
                boxShadow: active
                    ? const [
                        BoxShadow(color: Color(0x38007BFF), blurRadius: 12),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    look.icon,
                    size: 21,
                    color: active ? Colors.white : Tokens.muted,
                  ),
                  if (active && !iconOnly) ...[const SizedBox(width: 8), label],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The View glyph chip: shows the key, and opens the look + sort menu so a
/// mouse or thumb can reach both without a keyboard.
class LibraryViewChip extends StatelessWidget {
  const LibraryViewChip({
    super.key,
    required this.onPressed,
    this.size = 40,
    this.tooltip = 'View options',
  });

  final VoidCallback onPressed;
  final double size;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              constraints: const BoxConstraints(minWidth: 30),
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x1ADDE6F4),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x2BFFFFFF)),
              ),
              child: Text(
                'V',
                style: Tokens.glyphChip.copyWith(color: Tokens.text, fontSize: 11),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The system chips: All games, Favorites, then one per system present, each
/// with its count (§8.1). The row scrolls when it cannot fit.
class LibraryChips extends StatelessWidget {
  const LibraryChips({
    super.key,
    required this.chips,
    required this.selectedId,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 44),
    this.height = 38,
    this.fontSize = 14,
    this.fade = true,
  });

  final List<LibraryFilterChip> chips;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final EdgeInsets padding;
  final double height;
  final double fontSize;

  /// Fade the trailing edge when the row can scroll.
  final bool fade;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: chips.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final chip = chips[i];
        return _Chip(
          chip: chip,
          active: chip.id == selectedId,
          height: height,
          fontSize: fontSize,
          onTap: () => onSelected(chip.id),
        );
      },
    );
    if (!fade) return SizedBox(height: height, child: list);
    return SizedBox(
      height: height,
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.985, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: list,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chip,
    required this.active,
    required this.height,
    required this.fontSize,
    required this.onTap,
  });

  final LibraryFilterChip chip;
  final bool active;
  final double height;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : Tokens.muted;
    return Semantics(
      button: true,
      selected: active,
      label: '${chip.label}, ${chip.count}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(height / 2),
          child: AnimatedContainer(
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0x33007BFF) // rgba(0,123,255,.2)
                  : const Color(0x0DDDE6F4), // rgba(221,230,244,.05)
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: active
                    ? const Color(0x99007BFF) // .6
                    : const Color(0x1FDDE6F4), // .12
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chip.label,
                  style: Tokens.body(
                    size: fontSize,
                    weight: FontWeight.w600,
                    color: fg,
                    height: null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${chip.count}',
                  style: Tokens.body(
                    size: fontSize,
                    weight: FontWeight.w500,
                    color: active
                        ? Colors.white.withValues(alpha: 0.6)
                        : Tokens.muted.withValues(alpha: 0.6),
                    height: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen title block: eyebrow, title and the count beside it (§8).
class LibraryTitle extends StatelessWidget {
  const LibraryTitle({
    super.key,
    this.title = 'The collection',
    required this.count,
    required this.titleSize,
    this.countSize = 16,
    this.eyebrowSize = 13,
    this.showEyebrow = true,
    this.showCount = true,
    this.compactCount = false,
  });

  final String title;
  final int count;
  final double titleSize;
  final double countSize;
  final double eyebrowSize;
  final bool showEyebrow;
  final bool showCount;

  /// Phones show just the number beside the title ("12"), as the phone frame
  /// does; every wider family spells out "12 games".
  final bool compactCount;

  @override
  Widget build(BuildContext context) {
    final label = compactCount
        ? '$count'
        : (count == 1 ? '1 game' : '$count games');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEyebrow) ...[
          Text(
            'YOUR GAMES. YOUR WAY.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.eyebrow.copyWith(
              fontSize: eyebrowSize < 12 ? 12 : eyebrowSize,
              letterSpacing: 0.30 * (eyebrowSize < 12 ? 12 : eyebrowSize),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.display(
                  size: titleSize,
                  weight: FontWeight.w600,
                  ls: -0.03 * titleSize,
                  height: 1,
                ),
              ),
            ),
            if (showCount) ...[
              const SizedBox(width: 14),
              Text(
                label,
                style: Tokens.body(
                  size: countSize,
                  color: Tokens.muted,
                  height: null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Focus the library search from anywhere with `/` or Ctrl/⌘ K.
List<ShortcutActivator> get librarySearchActivators => const [
  SingleActivator(LogicalKeyboardKey.slash),
  SingleActivator(LogicalKeyboardKey.keyK, control: true),
  SingleActivator(LogicalKeyboardKey.keyK, meta: true),
];

/// A system's short code (NES, GBA, PS1) for a chip or a cover.
String librarySystemCode(String system) => systemCode(system);
