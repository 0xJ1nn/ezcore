import 'package:flutter/material.dart';
import '../services/cover_art.dart';
import '../theme/tokens.dart';
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

/// The three destinations (layout option A). Settings is last; the rail
/// pins it to the bottom edge.
const orbitNavItems = [
  OrbitNavItem('library', 'Library', Icons.grid_view_outlined, Icons.grid_view),
  OrbitNavItem('cores', 'Cores', Icons.memory_outlined, Icons.memory),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = short ? 50.0 : 64.0;
          Widget button(OrbitNavItem it) => _RailButton(
            item: it,
            active: page == it.id,
            short: short,
            height: height,
            onTap: () => onGo(it.id),
          );
          final main = orbitNavItems.take(orbitNavItems.length - 1);
          return Column(
            children: [
              if (!short) ...[
                Semantics(
                  label: 'ezCORE',
                  child: Image.asset(
                    'assets/branding/icon-blue.png',
                    width: 34,
                    height: 34,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox(height: 34),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              for (final it in main) ...[button(it), SizedBox(height: short ? 4 : 10)],
              const Spacer(),
              button(orbitNavItems.last),
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
    final label = item.label;
    final foreground = active ? Colors.white : Tokens.muted;
    final compact = short && height < 44;
    final labelStyle = short
        ? TextStyle(
            fontFamily: Tokens.bodyFamily,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: foreground,
          )
        : Tokens.body(size: 9, color: foreground);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Material(
        color: active ? Tokens.chipActiveBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: height),
            padding: EdgeInsets.symmetric(
              vertical: short ? 2 : 12,
              horizontal: 3,
            ),
            decoration: active
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x21DDE6F4)),
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? item.filled : item.icon,
                  size: short ? (compact ? 16 : 18) : 21,
                  color: active ? Colors.white : Tokens.muted,
                ),
                SizedBox(height: short ? 2 : 8),
                ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
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

/// Game cover: the pinned screenshot capture when one exists, otherwise a
/// deterministic generative cover in the approved identity (stable per game).
class GameCover extends StatelessWidget {
  const GameCover({
    super.key,
    required this.gameId,
    required this.title,
    required this.system,
    this.width,
    this.height,
    this.radius = Tokens.radiusCover,
    this.selected = false,
    this.dimmed = false,
  });
  final String gameId;
  final String title;
  final String system;
  final double? width;
  final double? height;
  final double radius;
  final bool selected;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26364B), Color(0xFF111C2A)],
        ),
        border: Border.all(
          color: selected ? Colors.white : const Color(0x22DDE6F4),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0xBB000000),
                  offset: Offset(0, 26),
                  blurRadius: 55,
                ),
                BoxShadow(
                  color: Color(0x80007BFF),
                  blurRadius: 0,
                  spreadRadius: 6,
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x55000000),
                  offset: Offset(0, 10),
                  blurRadius: 24,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: coverRevision,
              builder: (_, revision, _) {
                final art = coverFileFor(gameId);
                if (art != null) {
                  PaintingBinding.instance.imageCache.evict(FileImage(art));
                }
                return art == null
                    ? _GenerativeArt(gameId: gameId)
                    : Image.file(
                        art,
                        // FileImage keys by path, so a revision key is needed
                        // to make same-path screenshot replacements reload.
                        key: ValueKey<String>('game-cover:$gameId:$revision'),
                        fit: BoxFit.cover,
                      );
              },
            ),
            // Spine edge + sheen.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: Container(color: Colors.white.withValues(alpha: 0.08)),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.8, -0.8),
                    end: const Alignment(0.4, 0.4),
                    colors: [
                      Colors.white.withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3],
                  ),
                ),
              ),
            ),
            if (dimmed)
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
            // Bottom label scrim.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (system.isNotEmpty)
                      Text(
                        system.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 7,
                          ls: 1.5,
                          color: Tokens.muted,
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: 11,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerativeArt extends StatelessWidget {
  const _GenerativeArt({required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CoverPainter(coverSpecFor(gameId)));
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.spec);
  final CoverSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(spec.top), Color(spec.bottom)],
        ).createShader(rect),
    );
    final accent = Color(spec.accent);
    final w = size.width, h = size.height;
    switch (spec.motif) {
      case 0: // Concentric rings, top-right.
        for (var i = 5; i >= 1; i--) {
          canvas.drawCircle(
            Offset(w * 0.78, h * 0.24),
            w * 0.12 * i,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = accent.withValues(alpha: 0.10 + 0.05 * (5 - i)),
          );
        }
      case 1: // Diagonal beams.
        for (var i = 0; i < 3; i++) {
          final y = h * (0.15 + 0.22 * i);
          final path = Path()
            ..moveTo(-w * 0.2, y + h * 0.28)
            ..lineTo(w * 0.6, y - h * 0.28)
            ..lineTo(w * 0.85, y - h * 0.28)
            ..lineTo(w * 0.05, y + h * 0.28)
            ..close();
          canvas.drawPath(
            path,
            Paint()..color = accent.withValues(alpha: 0.10 - 0.025 * i),
          );
        }
      case 2: // Dot grid, fading downward.
        for (var r = 0; r < 9; r++) {
          for (var c = 0; c < 7; c++) {
            canvas.drawCircle(
              Offset(w * (0.12 + 0.125 * c), h * (0.10 + 0.09 * r)),
              1.6,
              Paint()
                ..color = Colors.white.withValues(
                  alpha: (0.16 * (1 - r / 9)).clamp(0.02, 0.16),
                ),
            );
          }
        }
        canvas.drawCircle(
          Offset(w * 0.8, h * 0.72),
          w * 0.30,
          Paint()..color = accent.withValues(alpha: 0.12),
        );
      case 3: // Large offset disc + horizon line.
        canvas.drawCircle(
          Offset(w * 0.5, h * 1.02),
          w * 0.75,
          Paint()..color = accent.withValues(alpha: 0.14),
        );
        canvas.drawLine(
          Offset(0, h * 0.62),
          Offset(w, h * 0.62),
          Paint()
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.18),
        );
        canvas.drawCircle(
          Offset(w * 0.74, h * 0.30),
          w * 0.07,
          Paint()..color = Colors.white.withValues(alpha: 0.75),
        );
      default: // Arcs from bottom-left.
        for (var i = 1; i <= 4; i++) {
          canvas.drawArc(
            Rect.fromCircle(
              center: Offset(-w * 0.1, h * 1.05),
              radius: w * 0.28 * i,
            ),
            -1.2,
            0.9,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = accent.withValues(alpha: 0.08 + 0.04 * i),
          );
        }
    }
    // Vignette.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.5, 0.45),
          radius: 1.1,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      old.spec.top != spec.top ||
      old.spec.bottom != spec.bottom ||
      old.spec.motif != spec.motif ||
      old.spec.accent != spec.accent;
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

