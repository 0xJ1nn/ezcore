import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cover_art.dart';
import '../theme/tokens.dart';

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

/// Ambient background: near-black + faint blue ellipse + 1px diagonal beam.
/// The beam breathes (9s, like the finalized edge-light) unless [motion]
/// is off or the OS requests reduced motion.
class Ambient extends StatefulWidget {
  const Ambient({super.key, this.selectedLabel = '', this.motion = true});
  final String selectedLabel;
  final bool motion;

  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    if (widget.motion) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Ambient old) {
    super.didUpdateWidget(old);
    if (widget.motion != old.motion) {
      if (widget.motion) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.stop();
        _ctrl.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final beam = Transform.rotate(
      angle: 38 * 3.14159 / 180,
      child: Container(
        width: 1,
        height: height * 1.8,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Color(0x40DDE6F4),
              Color(0x70007BFF),
              Colors.transparent,
            ],
          ),
          boxShadow: [
            BoxShadow(color: Color(0x30007BFF), blurRadius: 15),
          ],
        ),
      ),
    );
    return Stack(
      children: [
        Container(color: Tokens.bg),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, 0.7),
                radius: 0.9,
                colors: [Color(0x0D007BFF), Colors.transparent],
                stops: [0.0, 0.55],
              ),
            ),
          ),
        ),
        // Diagonal edge-light beam.
        Positioned(
          left: width * 0.74,
          top: -200,
          child: (widget.motion && !reduce)
              ? AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Opacity(
                    opacity: 0.4 - 0.25 * _ctrl.value,
                    child: child,
                  ),
                  child: beam,
                )
              : Opacity(opacity: 0.4, child: beam),
        ),
      ],
    );
  }
}

class OrbitTopbar extends StatelessWidget {
  const OrbitTopbar({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final clock = StreamBuilder<DateTime>(
      stream: Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final d = snap.data ?? DateTime.now();
        final hh = d.hour.toString().padLeft(2, '0');
        final mm = d.minute.toString().padLeft(2, '0');
        return Text('$hh:$mm', style: Tokens.display(size: 12, ls: 0));
      },
    );
    return SizedBox(
      height: compact ? 44 : 72,
      child: Row(
        children: [
          Text('ezCORE',
              style: Tokens.display(size: 20, weight: FontWeight.w700, ls: -1.0)),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: Tokens.accent, shape: BoxShape.circle),
          ),
          const Spacer(),
          const Icon(Icons.wifi, size: 15, color: Tokens.muted),
          const SizedBox(width: 10),
          clock,
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x10DDE6F4),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0x30007BFF)),
            ),
            child: Text('P1',
                style: Tokens.display(size: 11, weight: FontWeight.w600, ls: 0)),
          ),
        ],
      ),
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
  OrbitNavItem('systems', 'Systems', Icons.sports_esports_outlined, Icons.sports_esports),
  OrbitNavItem('vault', 'Capsule', Icons.history_outlined, Icons.history),
  OrbitNavItem('settings', 'Settings', Icons.settings_outlined, Icons.settings),
];

/// Landscape left command rail (84px, 72px short).
class OrbitRail extends StatelessWidget {
  const OrbitRail({super.key, required this.page, required this.onGo, this.short = false});
  final String page;
  final ValueChanged<String> onGo;
  final bool short;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: short ? Tokens.railShort : Tokens.rail,
      decoration: const BoxDecoration(
        color: Color(0xCC0A0A0A),
        border: Border(right: BorderSide(color: Color(0x16DDE6F4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final it in orbitNavItems)
            Padding(
              padding: EdgeInsets.only(bottom: short ? 6 : 12),
              child: _RailButton(
                item: it,
                active: page == it.id,
                short: short,
                onTap: () => onGo(it.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item, required this.active, required this.short, required this.onTap});
  final OrbitNavItem item;
  final bool active;
  final bool short;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = item.id == 'vault' ? 'Capsule' : item.label;
    return Material(
      color: active ? Tokens.chipActiveBg : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: short ? 54 : 64),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
          decoration: active
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x21DDE6F4)),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? item.filled : item.icon,
                  size: short ? 18 : 21,
                  color: active ? Colors.white : Tokens.muted),
              const SizedBox(height: 8),
              Text(label,
                  style: Tokens.body(
                      size: short ? 8 : 9,
                      color: active ? Colors.white : Tokens.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Portrait top command dock (50px rounded translucent).
class OrbitDockNav extends StatelessWidget {
  const OrbitDockNav({super.key, required this.page, required this.onGo});
  final String page;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0x990A0A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x20DDE6F4)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final it in orbitNavItems)
            Expanded(
              child: _DockButton(
                item: it,
                active: page == it.id,
                onTap: () => onGo(it.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.item, required this.active, required this.onTap});
  final OrbitNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = item.id == 'vault' ? 'Capsule' : item.label;
    return Material(
      color: active ? Tokens.chipActiveBg : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? item.filled : item.icon,
                  size: 16, color: active ? Colors.white : Tokens.muted),
              const SizedBox(width: 5),
              Text(label,
                  style: Tokens.body(
                      size: 9, color: active ? Colors.white : Tokens.muted)),
            ],
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
                colors: [Color(0xFF2A3542), Color(0xFF1B222C)])
            : const LinearGradient(
                colors: [Tokens.accentHi, Tokens.accentDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        boxShadow: onPressed == null
            ? null
            : const [
                BoxShadow(color: Color(0x45FFFFFF), offset: Offset(0, 1), blurRadius: 0),
                BoxShadow(color: Color(0x22007BFF), offset: Offset(0, 5), blurRadius: 18),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Text(label,
              style: Tokens.display(size: 12, weight: FontWeight.w800, ls: 0, color: Colors.white)),
        ],
      ),
    );
    final child = expanded
        ? SizedBox(width: double.infinity, child: Center(child: btn))
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
                        ? const LinearGradient(colors: [Color(0xFF2A3542), Color(0xFF1B222C)])
                        : const LinearGradient(colors: [Tokens.accentHi, Tokens.accentDeep]),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(label,
                          style: Tokens.display(
                              size: 12, weight: FontWeight.w800, ls: 0, color: Colors.white)),
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
  const OrbitSecondary({super.key, required this.label, required this.onPressed, this.icon});
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
  const OrbitRoundButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.active = false});
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
                  color: active ? Tokens.accent : const Color(0x26DDE6F4)),
            ),
            child: Icon(icon,
                size: 20, color: active ? Tokens.accent : Tokens.text),
          ),
        ),
      ),
    );
  }
}

class OrbitSearch extends StatelessWidget {
  const OrbitSearch({super.key, required this.controller, required this.onChanged, this.hint = 'Find a game'});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: Tokens.searchIdle,
        borderRadius: BorderRadius.circular(8),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Tokens.line),
            ),
            child: Text('/', style: Tokens.body(size: 10, color: Tokens.muted)),
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
              onTap: () => onView('flow')),
          _SwBtn(
              icon: Icons.grid_view_outlined,
              active: view == 'grid',
              tooltip: 'Grid view',
              onTap: () => onView('grid')),
        ],
      ),
    );
  }
}

class _SwBtn extends StatelessWidget {
  const _SwBtn({required this.icon, required this.active, required this.onTap, required this.tooltip});
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
            child: Icon(icon,
                size: 17, color: active ? Colors.white : Tokens.muted),
          ),
        ),
      ),
    );
  }
}

class OrbitToggle extends StatelessWidget {
  const OrbitToggle({super.key, required this.value, required this.onChanged, this.label = ''});
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
  const OrbitSelect({super.key, required this.value, required this.options, required this.onChanged, this.labels});
  final T value;
  final List<T> options;
  final ValueChanged<T?> onChanged;
  final Map<T, String>? labels;

  @override
  Widget build(BuildContext context) {
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
          value: value,
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

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.count,
    this.trailing,
  });
  final String eyebrow;
  final String title;
  final String? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow.toUpperCase(), style: Tokens.eyebrow),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(title,
                        style: Tokens.h1, overflow: TextOverflow.ellipsis),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Text(count!, style: Tokens.body(size: 10, color: Tokens.muted)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 14), trailing!],
      ],
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

/// Underline-style collection chip (final-01): no pill, 2px blue bar when active.
class OrbitChip extends StatelessWidget {
  const OrbitChip({
    super.key,
    required this.label,
    this.sub,
    required this.active,
    required this.onTap,
    this.icon,
    this.height = 50,
  });
  final String label;
  final String? sub;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: active
                ? const Border(bottom: BorderSide(color: Tokens.accent, width: 2))
                : null,
            boxShadow: active
                ? const [BoxShadow(color: Color(0x50007BFF), blurRadius: 12, offset: Offset(0, 6))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: active ? Colors.white : Tokens.muted),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: Tokens.chipLabel.copyWith(
                      color: active ? Colors.white : Tokens.muted)),
              if (sub != null) ...[
                const SizedBox(width: 6),
                Text(sub!,
                    style: Tokens.display(size: 8, ls: 0.1, color: Tokens.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OrbitFooter extends StatelessWidget {
  const OrbitFooter({super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _Hint(keys: const ['←', '→'], label: 'Browse'),
          const SizedBox(width: 18),
          _Hint(keys: const ['↵'], label: 'Game details'),
          const SizedBox(width: 18),
          _Hint(keys: const ['ESC'], label: 'Back'),
          const SizedBox(width: 18),
          _Hint(keys: const ['1–4'], label: 'Switch space'),
          const Spacer(),
          Row(
            children: [
              Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                      color: Tokens.separator, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('BUILT FOR GAMES. YOUR GAMES. YOUR WAY.',
                  style: Tokens.body(size: 8, ls: 1.0, color: Tokens.muted)),
            ],
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
    final art = coverFileFor(gameId);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232B36), Color(0xFF12151C)],
        ),
        border: Border.all(
          color: selected ? Colors.white : const Color(0x22DDE6F4),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(color: Color(0xBB000000), offset: Offset(0, 26), blurRadius: 55),
                BoxShadow(color: Color(0x80007BFF), blurRadius: 0, spreadRadius: 6),
              ]
            : const [BoxShadow(color: Color(0x55000000), offset: Offset(0, 10), blurRadius: 24)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (art != null)
              Image.file(art, fit: BoxFit.cover)
            else
              _GenerativeArt(gameId: gameId),
            // Spine edge + sheen.
            Positioned(
              left: 0, top: 0, bottom: 0, width: 4,
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
              left: 0, right: 0, bottom: 0,
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
                      Text(system.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tokens.body(
                              size: 7, ls: 1.5, color: Tokens.muted)),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                            size: 11,
                            weight: FontWeight.w600,
                            color: Colors.white)),
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
                    alpha: (0.16 * (1 - r / 9)).clamp(0.02, 0.16)),
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
                center: Offset(-w * 0.1, h * 1.05), radius: w * 0.28 * i),
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
  const CoreScopes(
      {super.key, required this.scope, required this.onScope, this.expand = false});
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
  const _ScopeBtn({required this.label, required this.active, required this.onTap});
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
          child: Text(label,
              style: Tokens.body(
                  size: 11, color: active ? Colors.white : Tokens.muted)),
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
            child: child),
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
