import 'dart:async';
import 'package:flutter/material.dart';
import '../models/game_entry.dart';
import '../services/cover_art.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
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

/// The ezCORE lockup (brand mark + wordmark).
///
/// Uses the committed brand asset so the mark can never drift from
/// `assets/branding/`. If the asset is missing for any reason the widget
/// falls back to the wordmark in display type — the shell still reads.
class OrbitBrand extends StatelessWidget {
  const OrbitBrand({super.key, this.height = 26, this.onTap});

  /// Target lockup height in logical pixels.
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lockup = Image.asset(
      'assets/branding/lockup-light.png',
      height: height,
      // The asset is 950px wide; keep it sharp without letting it eat
      // the row at large text scales.
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stack) => _Wordmark(height: height),
    );
    if (onTap == null) return lockup;
    return Semantics(
      button: true,
      label: 'ezCORE home',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: lockup,
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Text(
      'ezCORE',
      style: Tokens.display(
        size: height * 0.86,
        weight: FontWeight.w700,
        ls: -1.0,
      ),
    );
  }
}

/// Top command bar.
///
/// Desktop/tablet: optional leading control, brand, status cluster.
/// Phone portrait: leading control, centred brand, trailing control —
/// the studio plate's arrangement.
class OrbitTopbar extends StatelessWidget {
  const OrbitTopbar({
    super.key,
    this.compact = false,
    this.leading,
    this.trailing,
    this.centered = false,
  });

  final bool compact;
  final Widget? leading;
  final Widget? trailing;

  /// Phone-portrait arrangement: leading, centred brand, trailing.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final brand = OrbitBrand(height: compact ? 20.0 : (centered ? 22.0 : 26.0));
    final height = compact ? 44.0 : (centered ? 52.0 : 60.0);

    if (centered) {
      return SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (leading != null)
              Align(alignment: Alignment.centerLeft, child: leading),
            brand,
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          brand,
          const Spacer(),
          if (trailing != null) trailing! else const OrbitStatusCluster(),
        ],
      ),
    );
  }
}

/// Right-hand status: local player badge + clock. Nothing leaves the
/// device, so this is purely a glanceable local readout.
class OrbitStatusCluster extends StatelessWidget {
  const OrbitStatusCluster({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final clock = StreamBuilder<DateTime>(
      stream: Stream.periodic(
        const Duration(seconds: 30),
        (_) => DateTime.now(),
      ),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final d = snap.data ?? DateTime.now();
        final hh = d.hour.toString().padLeft(2, '0');
        final mm = d.minute.toString().padLeft(2, '0');
        return Text('$hh:$mm', style: Tokens.display(size: 12, ls: 0));
      },
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          const Icon(Icons.wifi, size: 15, color: Tokens.muted),
          const SizedBox(width: 10),
        ],
        clock,
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x10DDE6F4),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0x30007BFF)),
          ),
          child: Text(
            'P1',
            style: Tokens.display(size: 11, weight: FontWeight.w600, ls: 0),
          ),
        ),
      ],
    );
  }
}

class OrbitNavItem {
  const OrbitNavItem(this.id, this.label, this.icon, this.filled);
  final String id;
  final String label;
  final IconData icon;
  final IconData filled;
}

const orbitNavItems = [
  OrbitNavItem('library', 'Library', Icons.grid_view_outlined, Icons.grid_view),
  OrbitNavItem(
    'systems',
    'Systems',
    Icons.sports_esports_outlined,
    Icons.sports_esports,
  ),
  OrbitNavItem('vault', 'Capsule', Icons.history_outlined, Icons.history),
  OrbitNavItem('settings', 'Settings', Icons.settings_outlined, Icons.settings),
];

/// Desktop/landscape rail adds two common library shortcuts. Phone portrait
/// keeps the quieter four-item bottom bar in [orbitNavItems].
const orbitRailItems = [
  OrbitNavItem('library', 'Library', Icons.grid_view_outlined, Icons.grid_view),
  OrbitNavItem(
    'systems',
    'Systems',
    Icons.sports_esports_outlined,
    Icons.sports_esports,
  ),
  OrbitNavItem(
    'continue',
    'Continue',
    Icons.play_circle_outline,
    Icons.play_circle,
  ),
  OrbitNavItem(
    'favorites',
    'Favorites',
    Icons.favorite_outline,
    Icons.favorite,
  ),
  OrbitNavItem('vault', 'Capsule', Icons.history_outlined, Icons.history),
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
          const count = 6;
          const verticalPadding = 28.0;
          final gap = short ? 2.0 : 12.0;
          final available = constraints.maxHeight - verticalPadding;
          final fittedHeight = short
              ? ((available - gap * (count - 1)) / count).clamp(48.0, 50.0)
              : 64.0;
          final fits = available >= fittedHeight * count + gap * (count - 1);
          final column = Column(
            mainAxisAlignment: fits
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              for (var i = 0; i < orbitRailItems.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == orbitRailItems.length - 1 ? 0 : gap,
                  ),
                  child: _RailButton(
                    item: orbitRailItems[i],
                    active: page == orbitRailItems[i].id,
                    short: short,
                    height: fittedHeight,
                    onTap: () => onGo(orbitRailItems[i].id),
                  ),
                ),
            ],
          );
          return fits ? column : SingleChildScrollView(child: column);
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
    final label = item.id == 'vault' ? 'Capsule' : item.label;
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

class OrbitRoundButton extends StatelessWidget {
  const OrbitRoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: const Color(0x0ADDE6F4),
        borderRadius: BorderRadius.circular(Tokens.radiusRound),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusRound),
          onTap: onPressed,
          child: Container(
            width: 48,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusRound),
              border: Border.all(
                color: active ? Tokens.accent : const Color(0x26DDE6F4),
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? Tokens.accent : Tokens.text,
            ),
          ),
        ),
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

class OrbitSwitcher extends StatelessWidget {
  const OrbitSwitcher({super.key, required this.view, required this.onView});
  final String view; // 'flow' | 'grid'
  final ValueChanged<String> onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.searchIdle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Tokens.line),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SwBtn(
            icon: Icons.view_carousel_outlined,
            active: view == 'flow',
            tooltip: 'Cover Flow view',
            onTap: () => onView('flow'),
          ),
          _SwBtn(
            icon: Icons.grid_view_outlined,
            active: view == 'grid',
            tooltip: 'Grid view',
            onTap: () => onView('grid'),
          ),
        ],
      ),
    );
  }
}

class _SwBtn extends StatelessWidget {
  const _SwBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Tokens.chipActiveBg : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: 38,
            width: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 17,
              color: active ? Colors.white : Tokens.muted,
            ),
          ),
        ),
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

class SystemLabel extends StatelessWidget {
  const SystemLabel({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Tokens.systemLabelBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Tokens.systemLabelBd),
      ),
      child: Text(text.toUpperCase(), style: Tokens.systemLabel),
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

/// Segmented pill tabs — All / Favorites / Recent (studio plate).
class OrbitTabs extends StatelessWidget {
  const OrbitTabs({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 38,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final double height;

  static const tabs = <String, String>{
    'all': 'All',
    'favorites': 'Favorites',
    'recent': 'Recent',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x66070B12),
        borderRadius: BorderRadius.circular(Tokens.pillRadius),
        border: Border.all(color: Tokens.line),
      ),
      // Narrow phones cannot fit three fixed pills: shrink the padding
      // (and the type) instead of overflowing.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxWidth < 330;
          return Row(
            children: [
              for (final e in tabs.entries)
                Expanded(
                  child: _TabButton(
                    label: e.value,
                    active: value == e.key,
                    height: height - 8,
                    tight: tight,
                    onTap: () => onChanged(e.key),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.height,
    this.tight = false,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double height;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? Tokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(Tokens.pillRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.pillRadius),
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: tight ? 6 : 18),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Tokens.body(
                size: tight ? 10 : 11,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? Colors.white : Tokens.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title with an optional "See all" action.
class OrbitSectionHeader extends StatelessWidget {
  const OrbitSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
  });
  final String title;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Tokens.sectionTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(seeAllLabel, style: Tokens.sectionLink),
          ),
      ],
    );
  }
}

/// Footer: keyboard hints plus the two brand taglines from the studio plate.
class OrbitFooter extends StatelessWidget {
  const OrbitFooter({super.key, this.hints = true});
  final bool hints;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (hints) ...[
            _Hint(keys: const ['←', '→'], label: 'Browse'),
            const SizedBox(width: 18),
            _Hint(keys: const ['↵'], label: 'Game details'),
            const Spacer(),
          ] else
            const Spacer(),
          Text(
            Tokens.taglineLeft,
            style: Tokens.body(size: 8, ls: 1.6, color: Tokens.muted),
          ),
          const SizedBox(width: 18),
          Text(
            Tokens.taglineRight,
            style: Tokens.body(size: 8, ls: 1.6, color: Tokens.muted),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.label});
  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys)
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Tokens.line),
            ),
            child: Text(k, style: Tokens.body(size: 9, color: Tokens.muted)),
          ),
        const SizedBox(width: 4),
        Text(label, style: Tokens.footerStyle),
      ],
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

/// Core scopes segmented control (All / Added / Available).
class CoreScopes extends StatelessWidget {
  const CoreScopes({
    super.key,
    required this.scope,
    required this.onScope,
    this.expand = false,
  });
  final String scope;
  final ValueChanged<String> onScope;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x880A0A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1BDDE6F4)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in const ['all', 'added', 'available'])
            expand
                ? Expanded(
                    child: _ScopeBtn(
                      label: s == 'all'
                          ? 'All cores'
                          : s[0].toUpperCase() + s.substring(1),
                      active: scope == s,
                      onTap: () => onScope(s),
                    ),
                  )
                : _ScopeBtn(
                    label: s == 'all'
                        ? 'All cores'
                        : s[0].toUpperCase() + s.substring(1),
                    active: scope == s,
                    onTap: () => onScope(s),
                  ),
        ],
      ),
    );
  }
}

class _ScopeBtn extends StatelessWidget {
  const _ScopeBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Tokens.chipActiveBg : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: active
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0x14DDE6F4)),
                )
              : null,
          child: Text(
            label,
            style: Tokens.body(
              size: 11,
              color: active ? Colors.white : Tokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showOrbitDialog<T>(BuildContext context, Widget dialog) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Tokens.scrim,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Tokens.ease);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 890, maxHeight: 640),
          child: Material(
            color: Colors.transparent,
            child: Container(decoration: Tokens.dialogDecor, child: dialog),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Studio-plate composite pieces
//
// The selected-game dock, the stat panel, section tiles, the phone command
// bar, and the "Select system" sheet. Every value shown here is read from
// the library entry — nothing is estimated or filled in.
// ---------------------------------------------------------------------------

/// One row of the stat panel: small muted label, real value.
class OrbitStatRow extends StatelessWidget {
  const OrbitStatRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: Tokens.statLabel)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Tokens.statValue.copyWith(
                color: valueColor ?? Tokens.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tick per saved snapshot.
///
/// The studio plate shows a "completion" bar here. ezCORE has no
/// completion data, and inventing one would be a lie — so the same slot
/// carries the one progress signal the app truly owns: how many moments
/// you have saved for this game.
class SnapshotTicks extends StatelessWidget {
  const SnapshotTicks({super.key, required this.count, this.max = 10});
  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Text('No snapshots yet', style: Tokens.statLabel);
    }
    final shown = count.clamp(0, max);
    return Row(
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            width: 12,
            height: 4,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Tokens.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        if (count > max) Text('+$count-$max', style: Tokens.statLabel),
      ],
    );
  }
}

/// Stats for the selected game, using only tracked fields.
class GameStatPanel extends StatelessWidget {
  const GameStatPanel({super.key, required this.game, this.dense = false});
  final GameEntry game;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, dense ? 10 : 14, 14, dense ? 10 : 14),
      decoration: Tokens.statPanelDecor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitStatRow(
            label: 'Last played',
            value: lastPlayedLabel(game.lastPlayedMs),
          ),
          OrbitStatRow(
            label: 'Save states',
            value: countLabel(game.stateCount, 'state'),
          ),
          OrbitStatRow(
            label: 'Cheats on',
            value: countLabel(game.cheatsOn, 'code'),
            valueColor: game.cheatsOn > 0 ? Tokens.accent : null,
          ),
          OrbitStatRow(label: 'File size', value: fileSizeLabel(game.fileSize)),
          const SizedBox(height: 6),
          SnapshotTicks(count: game.stateCount),
        ],
      ),
    );
  }
}

/// Action row under the selected game: Manage / Cheats / States / More.
class GameActionRow extends StatelessWidget {
  const GameActionRow({
    super.key,
    required this.game,
    required this.onManage,
    required this.onCheats,
    required this.onStates,
    required this.onMore,
  });
  final GameEntry game;
  final VoidCallback onManage;
  final VoidCallback onCheats;
  final VoidCallback onStates;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _DockAction(icon: Icons.tune, label: 'Manage', onTap: onManage),
        _DockAction(
          icon: Icons.bolt_outlined,
          label: 'Cheats (${game.cheatsOn})',
          onTap: onCheats,
        ),
        _DockAction(
          icon: Icons.save_outlined,
          label: 'States (${game.stateCount})',
          onTap: onStates,
        ),
        _DockAction(icon: Icons.more_horiz, label: 'More', onTap: onMore),
      ],
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: Tokens.body(size: 11, color: Tokens.text)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: const Color(0x0ADDE6F4),
        side: const BorderSide(color: Color(0x26DDE6F4)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
        ),
        foregroundColor: Tokens.text,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Cover tile used by the section rows ("Continue playing", "Recently added").
class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.game,
    required this.onTap,
    required this.footnote,
    this.width = 104,
  });
  final GameEntry game;
  final VoidCallback onTap;

  /// The honest one-line fact under the title (e.g. "2 days ago").
  final String footnote;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // The cover absorbs whatever height the row gives us, so the
          // text block can never overflow a short viewport.
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: GameCover(
                gameId: game.id,
                title: game.title,
                system: shortSystemLabel(game.system),
                width: width,
                radius: Tokens.radiusCover,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 18,
              child: Text(
                game.title,
                style: Tokens.body(size: 11, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 16,
              child: Text(
                footnote,
                style: Tokens.body(size: 9, color: Tokens.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 5),
            SnapshotTicks(count: game.stateCount, max: 6),
          ],
        ),
      ),
    );
  }
}

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
    final label = item.id == 'vault' ? 'Capsule' : item.label;
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

/// A row in the "Select system" sheet.
class SystemPickerRow extends StatelessWidget {
  const SystemPickerRow({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0x26007BFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.videogame_asset_outlined,
                  size: 18,
                  color: selected ? Tokens.accent : Tokens.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Tokens.body(
                      size: 12,
                      color: selected ? Colors.white : Tokens.text,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: Tokens.body(size: 10, color: Tokens.muted),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: selected ? Tokens.accent : Tokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the grouped "Select system" sheet.
///
/// [counts] maps a system id to how many games the library holds for it;
/// [onPick] receives the chosen filter (`null` = all systems).
Future<void> showSystemPicker(
  BuildContext context, {
  required Map<String, int> counts,
  required String selected,
  required ValueChanged<String?> onPick,
  int favoriteCount = 0,
}) {
  // Group by manufacturer, keeping the plate's section order.
  final grouped = <String, List<MapEntry<String, int>>>{};
  for (final e in counts.entries) {
    (grouped[makerFor(e.key)] ??= []).add(e);
  }
  for (final list in grouped.values) {
    list.sort(
      (a, b) => shortSystemLabel(
        a.key,
      ).toLowerCase().compareTo(shortSystemLabel(b.key).toLowerCase()),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scroll) => Container(
          decoration: Tokens.sheetDecor,
          child: SafeArea(
            top: false,
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Tokens.separator,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select system',
                        style: Tokens.display(
                          size: 19,
                          weight: FontWeight.w600,
                          ls: -0.4,
                        ),
                      ),
                    ),
                    OrbitRoundButton(
                      icon: Icons.close,
                      tooltip: 'Close system picker',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SystemPickerRow(
                  label: 'All systems',
                  count: counts.values.fold<int>(0, (a, b) => a + b),
                  selected: selected == 'All systems',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onPick(null);
                  },
                ),
                SystemPickerRow(
                  label: 'Favorites',
                  count: favoriteCount,
                  selected: selected == 'Favorites',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onPick('Favorites');
                  },
                ),
                for (final maker in systemMakerOrder)
                  if (grouped[maker] != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                      child: Text(maker.toUpperCase(), style: Tokens.eyebrow),
                    ),
                    for (final e in grouped[maker]!)
                      SystemPickerRow(
                        label: shortSystemLabel(e.key),
                        count: e.value,
                        selected: selected == e.key,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onPick(e.key);
                        },
                      ),
                  ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
