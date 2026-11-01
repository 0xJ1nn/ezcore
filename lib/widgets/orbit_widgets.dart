import 'package:flutter/material.dart';

import '../services/cover_art.dart';
import '../services/system_labels.dart';
import '../theme/tokens.dart';
import 'orbit_cover.dart';
import 'space_backdrop.dart';

/// Shared Orbit console chrome — final-01.
/// Topbar, nav rail/dock, ambient, docks, buttons, strips, toggles, toasts.

void orbitToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: Tokens.body(size: 12, color: Colors.white)),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 24, right: 24),
    ),
  );
}

/// Background for the shell. See `SpaceBackdrop` for the scene itself.
///
/// Kept as a thin wrapper so screens and tests can keep referring to
/// `Ambient` while the implementation lives in its own file.
class Ambient extends StatelessWidget {
  const Ambient({super.key, this.motion = true});
  final bool motion;

  @override
  Widget build(BuildContext context) =>
      Positioned.fill(child: SpaceBackdrop(motion: motion));
}

class OrbitNavItem {
  const OrbitNavItem(this.id, this.label, this.icon, this.filled);
  final String id;
  final String label;
  final IconData icon;
  final IconData filled;
}

/// The four spaces of the OS, in order (keys 1–4): your games, the systems
/// that play them (cores), the time capsule of saves, and settings.
const orbitNavItems = [
  OrbitNavItem('library', 'Library', Icons.grid_view_outlined, Icons.grid_view),
  OrbitNavItem(
    'cores',
    'Systems',
    Icons.sports_esports_outlined,
    Icons.sports_esports,
  ),
  OrbitNavItem('capsule', 'Capsule', Icons.history_outlined, Icons.history),
  OrbitNavItem('settings', 'Settings', Icons.settings_outlined, Icons.settings),
];

/// Landscape left command rail (84px, 72px short).
class OrbitRail extends StatelessWidget {
  const OrbitRail({
    super.key,
    required this.page,
    required this.onGo,
    this.short = false,
  });
  final String page;
  final ValueChanged<String> onGo;
  final bool short;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: short ? Tokens.railShort : Tokens.rail,
      decoration: const BoxDecoration(
        color: Color(0xE608101C),
        border: Border(right: BorderSide(color: Color(0x16DDE6F4))),
      ),
      padding: EdgeInsets.symmetric(horizontal: short ? 8 : 10, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = short ? 50.0 : 84.0;
          // The tagline only where there is room under the four spaces.
          final tagline = !short && constraints.maxHeight >= 560;
          return Column(
            children: [
              for (final it in orbitNavItems) ...[
                _RailButton(
                  item: it,
                  active: page == it.id,
                  short: short,
                  height: height,
                  onTap: () => onGo(it.id),
                ),
                SizedBox(height: short ? 4 : 12),
              ],
              const Spacer(),
              if (tagline)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in const ['PLAY', 'PRESERVE', 'ANYWHERE'])
                          Text(
                            w,
                            // Decorative small caps, hidden from screen
                            // readers, so below the 12 px body floor.
                            style: const TextStyle(
                              fontFamily: Tokens.bodyFamily,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.6,
                              color: Tokens.muted,
                              height: 1.9,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Container(width: 26, height: 2, color: Tokens.accent),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.active,
    required this.short,
    required this.height,
    required this.onTap,
  });
  final OrbitNavItem item;
  final bool active;
  final bool short;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Tokens.muted;
    final radius = BorderRadius.circular(short ? 10 : 14);
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: AnimatedContainer(
        duration: Tokens.fastDur,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x40007BFF), Color(0x14007BFF)],
                )
              : null,
          border: Border.all(
            color: active ? const Color(0xB3007BFF) : Colors.transparent,
            width: 1.2,
          ),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x55007BFF), blurRadius: 18)]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: height),
              padding: EdgeInsets.symmetric(
                vertical: short ? 2 : 10,
                horizontal: 3,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? item.filled : item.icon,
                    size: short ? 18 : 26,
                    color: foreground,
                  ),
                  SizedBox(height: short ? 2 : 8),
                  ExcludeSemantics(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: short ? 10 : 12.5,
                        weight: active ? FontWeight.w600 : FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Buttons ----

class OrbitPrimary extends StatelessWidget {
  const OrbitPrimary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.play_arrow,
    this.expanded = false,
    this.minHeight = 52,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool expanded;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 25),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
        gradient: onPressed == null
            ? const LinearGradient(
                colors: [Color(0xFF2A3542), Color(0xFF1B222C)],
              )
            : const LinearGradient(
                colors: [Tokens.accentHi, Tokens.accentDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        boxShadow: onPressed == null
            ? null
            : const [
                BoxShadow(
                  color: Color(0x45FFFFFF),
                  offset: Offset(0, 1),
                  blurRadius: 0,
                ),
                BoxShadow(
                  color: Color(0x22007BFF),
                  offset: Offset(0, 5),
                  blurRadius: 18,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            label,
            style: Tokens.display(
              size: 12,
              weight: FontWeight.w800,
              ls: 0,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
    final child = expanded
        ? SizedBox(
            width: double.infinity,
            child: Center(child: btn),
          )
        : btn;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
          onTap: onPressed,
          child: expanded
              ? Container(
                  constraints: BoxConstraints(minHeight: minHeight),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
                    gradient: onPressed == null
                        ? const LinearGradient(
                            colors: [Color(0xFF2A3542), Color(0xFF1B222C)],
                          )
                        : const LinearGradient(
                            colors: [Tokens.accentHi, Tokens.accentDeep],
                          ),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: Tokens.display(
                          size: 12,
                          weight: FontWeight.w800,
                          ls: 0,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : child,
        ),
      ),
    );
  }
}

class OrbitSecondary extends StatelessWidget {
  const OrbitSecondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon, size: 17) : const SizedBox.shrink(),
      label: Text(label, style: Tokens.body(size: 12, color: Tokens.text)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: const Color(0x0ADDE6F4),
        side: const BorderSide(color: Color(0x26DDE6F4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        foregroundColor: Tokens.text,
      ),
    );
  }
}

class OrbitSearch extends StatelessWidget {
  const OrbitSearch({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Find a game',
    this.shortcutLabel,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  /// Optional key hint shown at the trailing edge ("Ctrl K", "/").
  final String? shortcutLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: Tokens.searchIdle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Tokens.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Tokens.muted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: Tokens.body(size: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: Tokens.body(size: 13, color: Tokens.muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (shortcutLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Tokens.line),
              ),
              child: Text(
                shortcutLabel!,
                style: Tokens.body(size: 10, color: Tokens.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class OrbitToggle extends StatelessWidget {
  const OrbitToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '',
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            width: 38,
            height: 23,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: value ? Tokens.accent : Tokens.toggleOff,
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.white : Tokens.toggleKnobOff,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrbitSelect<T> extends StatelessWidget {
  const OrbitSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labels,
  });
  final T value;
  final List<T> options;
  final ValueChanged<T?> onChanged;
  final Map<T, String>? labels;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(value)
        ? value
        : options.isNotEmpty
        ? options.first
        : value;
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141922),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x20FFFFFF)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: const Color(0xFF141922),
          style: Tokens.body(size: 11),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(labels?[o] ?? '$o')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Collection chip — pill style, blue fill when active (studio plate).
class OrbitChip extends StatelessWidget {
  const OrbitChip({
    super.key,
    required this.label,
    this.sub,
    required this.active,
    required this.onTap,
    this.icon,
    this.height = 36,
  });
  final String label;
  final String? sub;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.pillRadius),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: Tokens.chipPill(active: active),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: active ? Colors.white : Tokens.muted,
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: Tokens.chipLabel.copyWith(
                    color: active ? Colors.white : Tokens.muted,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    sub!,
                    style: Tokens.display(
                      size: 8,
                      ls: 0.1,
                      color: Tokens.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Game cover: the pinned screenshot capture when one exists, otherwise the
/// generated mark-cut art ([OrbitCover] in the game's system hue.
class GameCover extends StatelessWidget {
  const GameCover({
    super.key,
    required this.gameId,
    required this.title,
    required this.systemId,
    this.sysShort,
    this.year,
    this.favorite = false,
    this.isNew = false,
    this.badgeText,
    this.badgeColor,
    this.width,
    this.height,
    this.radius = Tokens.radiusCover,
    this.dimmed = false,
  });

  final String gameId;
  final String title;

  /// System id ('nds', 'psx', …) — the cover's hue and default names derive
  /// from it.
  final String systemId;

  /// Compact code for the top row ('NDS', 'PS1', …); defaults to the design's
  /// code for [systemId].
  final String? sysShort;
  final int? year;
  final bool favorite;
  final bool isNew;

  /// A state-driven badge pill ('Needs core', 'Needs BIOS'). The screen owns
  /// the decision; the cover only paints it.
  final String? badgeText;
  final Color? badgeColor;

  final double? width;
  final double? height;
  final double radius;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final art = ValueListenableBuilder<int>(
      valueListenable: coverRevision,
      builder: (context, revision, _) {
        final file = coverFileFor(gameId);
        if (file != null) {
          return Image.file(
            file,
            // FileImage keys by path, so a revision key is needed to make
            // same-path screenshot replacements reload.
            key: ValueKey<String>('game-cover:$gameId:$revision'),
            fit: BoxFit.cover,
          );
        }
        return OrbitCover(
          title: title,
          systemId: systemId,
          sysShort: sysShort ?? systemCode(systemId),
          year: year,
          favorite: favorite,
          isNew: isNew,
          badgeText: badgeText,
          badgeColor: badgeColor,
          radius: radius,
        );
      },
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: dimmed
            ? Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x59000000)),
                  ),
                ],
              )
            : art,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Studio-plate composite pieces
//
// The selected-game dock, the stat panel, section tiles, the phone command
// bar, and the "Select system" sheet. Every value shown here is read from
// the library entry — nothing is estimated or filled in.
// ---------------------------------------------------------------------------

/// Compact square icon control for top bars.
class OrbitIconButton extends StatelessWidget {
  const OrbitIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: onPressed != null,
        child: Material(
          color: const Color(0x0ADDE6F4),
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
            onTap: onPressed,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                border: Border.all(
                  color: active ? Tokens.accent : const Color(0x26DDE6F4),
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: active ? Tokens.accent : Tokens.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone-portrait command bar — the plate's bottom navigation.
class OrbitBottomNav extends StatelessWidget {
  const OrbitBottomNav({super.key, required this.page, required this.onGo});
  final String page;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Tokens.bottomBarHeight,
      decoration: Tokens.bottomBarDecor,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final it in orbitNavItems)
              Expanded(
                child: _BottomNavButton(
                  item: it,
                  active: page == it.id,
                  onTap: () => onGo(it.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });
  final OrbitNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = item.label;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? item.filled : item.icon,
              size: 20,
              color: active ? Tokens.accent : Tokens.muted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Tokens.body(
                size: 9,
                color: active ? Tokens.text : Tokens.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
