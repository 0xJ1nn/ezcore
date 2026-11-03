import 'dart:async';

import 'package:flutter/material.dart';

import '../brand/brand_mark.dart';
import '../state/input_mode.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// The four spaces, in key order 1–4, plus Add games.
class _ChromeNav {
  const _ChromeNav(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const _chromeNav = <_ChromeNav>[
  _ChromeNav('library', 'Library', Symbols.gridView),
  _ChromeNav('cores', 'Systems', Symbols.sportsEsports),
  _ChromeNav('capsule', 'Capsule', Symbols.history),
  _ChromeNav('settings', 'Settings', Symbols.settings),
];

const _addGames = _ChromeNav('add', 'Add games', Symbols.addCircle);

/// The OS bar across the top of every destination (§7.2): the ezCORE
/// lockup, the "On this device" chip, the last input used, and the clock.
///
/// Sits at 76 px with the lockup 34 px high. The shell insets its left edge
/// past the rail and its right edge by 44.
class OrbitTopBar extends StatelessWidget {
  const OrbitTopBar({super.key, required this.compact, this.input, this.now});

  /// Phones: a shorter bar, the lockup alone plus the clock.
  final bool compact;

  /// Last input used; drives the icon and label.
  final InputModeController? input;

  /// The clock source (tests pin it).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 64 : 76,
      child: LayoutBuilder(
        builder: (context, c) {
          // The chip is the first thing to go when the bar gets tight; the
          // lockup, the input and the clock always stay.
          final showChip = !compact && c.maxWidth >= 700;
          return Row(
            children: [
              Transform.translate(
                offset: Offset(compact ? 0 : -3, 0),
                // The lockup asset is 34 px tall with 3 px of transparent
                // margin around the mark; 28 px draws the same art at the
                // design's visual height and width.
                child: BrandLockup(height: compact ? 22 : 28),
              ),
              const Spacer(),
              if (showChip) ...[const _DeviceChip(), const SizedBox(width: 22)],
              OrbitStatus(input: input, now: now, compact: compact),
            ],
          );
        },
      ),
    );
  }
}

/// "On this device": the privacy promise, stated where the account would be.
class _DeviceChip extends StatelessWidget {
  const _DeviceChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x0DDDE6F4), // rgba(221,230,244,.05)
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x1FDDE6F4)), // .12 ring
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.lock, size: 16, color: Tokens.muted),
          const SizedBox(width: 8),
          Text(
            'On this device',
            style: Tokens.body(size: 14, color: Tokens.muted, height: null),
          ),
        ],
      ),
    );
  }
}

/// Last input icon + label, then the clock in Space Grotesk 16/600.
class OrbitStatus extends StatefulWidget {
  const OrbitStatus({super.key, this.input, this.now, this.compact = false});

  final InputModeController? input;

  /// The clock source (tests pin it).
  final DateTime Function()? now;

  final bool compact;

  @override
  State<OrbitStatus> createState() => _OrbitStatusState();
}

class _OrbitStatusState extends State<OrbitStatus> {
  Timer? _tick;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.input?.addListener(_onInput);
    _schedule();
  }

  @override
  void didUpdateWidget(OrbitStatus old) {
    super.didUpdateWidget(old);
    if (old.input != widget.input) {
      old.input?.removeListener(_onInput);
      widget.input?.addListener(_onInput);
    }
  }

  void _onInput() {
    if (mounted) setState(() {});
  }

  /// Wake at the next minute boundary, not every second.
  void _schedule() {
    final now = _now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _tick = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.input?.removeListener(_onInput);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _now();
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final input = widget.input;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (input != null && !widget.compact) ...[
          Semantics(
            label: 'Last input: ${input.label}',
            child: Icon(input.icon, size: 20, color: Tokens.text),
          ),
          const SizedBox(width: 8),
          Text(
            input.label,
            style: Tokens.body(size: 14, color: Tokens.muted, height: null),
          ),
          const SizedBox(width: 22),
        ],
        Text(
          time,
          style: Tokens.display(
            size: widget.compact ? 14 : 16,
            weight: FontWeight.w600,
            ls: 0.32,
            color: Tokens.text,
            height: null,
          ),
        ),
      ],
    );
  }
}

/// The left command rail (§7.3): 104 px, four spaces, Add games, footer.
///
/// Every destination is an 80×76 card with a 26 px icon and a 12.5/600
/// label. Active items carry the blue gradient; focused items lift under the
/// shared halo. Phone landscape gets a compact 72 px rail.
class OrbitCommandRail extends StatelessWidget {
  const OrbitCommandRail({
    super.key,
    required this.page,
    required this.onGo,
    this.onAddGames,
    this.short = false,
  });

  final String page;
  final ValueChanged<String> onGo;
  final VoidCallback? onAddGames;
  final bool short;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final itemHeight = short ? (c.maxHeight < 400 ? 52.0 : 60.0) : 76.0;
        final showAdd = c.maxHeight >= (short ? 340 : 420);
        final showFooter = !short && c.maxHeight >= 560;
        final width = short ? Tokens.railShort : Tokens.rail;
        return Container(
          width: width,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xEB060B14), Color(0xB8060B14)],
            ),
            border: Border(right: BorderSide(color: Color(0x12FFFFFF))),
          ),
          padding: EdgeInsets.fromLTRB(
            short ? 8 : 0,
            short ? 16 : 96,
            short ? 8 : 0,
            short ? 12 : 28,
          ),
          child: Column(
            children: [
              for (final (i, item) in _chromeNav.indexed) ...[
                if (i > 0) SizedBox(height: short ? 8 : 10),
                _RailItem(
                  item: item,
                  active: page == item.id,
                  short: short,
                  height: itemHeight,
                  onTap: () => onGo(item.id),
                ),
              ],
              if (showAdd) ...[
                // The rail's 10 px gap plus the design's extra 18 px before
                // Add games; the CSS gap applies to the margin too.
                SizedBox(height: (short ? 8 : 10) + 18),
                _RailItem(
                  item: _addGames,
                  active: false,
                  short: short,
                  height: itemHeight,
                  onTap: onAddGames,
                ),
              ],
              const Spacer(),
              if (showFooter)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 80,
                      child: Text(
                        'PLAY\nPRESERVE\nANYWHERE',
                        // Decorative, hidden from screen readers: the design
                        // sets this footer at 11/1.9, and 12 px wraps.
                        style: Tokens.railFooter.copyWith(
                          fontSize: 11,
                          letterSpacing: 0.24 * 11,
                          height: 1.9,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.item,
    required this.active,
    required this.short,
    required this.height,
    required this.onTap,
  });

  final _ChromeNav item;
  final bool active;
  final bool short;
  final double height;
  final VoidCallback? onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final foreground = active ? Colors.white : Tokens.muted;
    final radius = BorderRadius.circular(16);
    final focused = _focus || _hover;

    final decoration = BoxDecoration(
      borderRadius: radius,
      gradient: active
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B5BD3), Color(0xFF06357A)],
            )
          : null,
      color: !active && focused ? const Color(0x1ADDE6F4) : null,
      border: active
          ? Border.all(color: const Color(0x994DA3FF))
          : Border.all(color: Colors.transparent),
      boxShadow: [
        if (active)
          const BoxShadow(
            color: Color(0x99007BFF),
            offset: Offset(0, 10),
            blurRadius: 30,
            spreadRadius: -8,
          ),
        if (_focus) ...Tokens.halo,
      ],
    );

    return Semantics(
      button: true,
      selected: active,
      label: widget.item.label,
      enabled: widget.onTap != null,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _focus && !widget.short ? 1.04 : 1,
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              width: double.infinity,
              height: widget.height,
              decoration: decoration,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.item.icon,
                    size: widget.short ? 22 : 26,
                    color: foreground,
                    fill: active ? 1 : 0,
                  ),
                  SizedBox(height: widget.short ? 4 : 7),
                  ExcludeSemantics(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: widget.short ? 11 : 12.5,
                        weight: FontWeight.w600,
                        color: foreground,
                        height: 1,
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

/// Phone-portrait command bar (§10): four spaces and Add games, 64 px.
class OrbitCommandBar extends StatelessWidget {
  const OrbitCommandBar({
    super.key,
    required this.page,
    required this.onGo,
    this.onAddGames,
  });

  final String page;
  final ValueChanged<String> onGo;
  final VoidCallback? onAddGames;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Tokens.bottomBarHeight,
      decoration: Tokens.bottomBarDecor,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in _chromeNav)
              Expanded(
                child: _CommandBarItem(
                  label: item.label,
                  icon: item.icon,
                  active: page == item.id,
                  onTap: () => onGo(item.id),
                ),
              ),
            Expanded(
              child: _CommandBarItem(
                label: 'Add',
                icon: Symbols.addCircle,
                active: false,
                onTap: onAddGames,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandBarItem extends StatelessWidget {
  const _CommandBarItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? Tokens.accent : Tokens.muted,
              fill: active ? 1 : 0,
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.body(
                  size: 10.5,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? Tokens.text : Tokens.muted,
                  height: null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keyboard hints along the foot of a screen: what each key does here.
class OrbitKeyHints extends StatelessWidget {
  const OrbitKeyHints({super.key, required this.hints});

  /// (keys, what they do).
  final List<(List<String>, String)> hints;

  @override
  Widget build(BuildContext context) {
    Widget key(String k) => Container(
      constraints: const BoxConstraints(minWidth: 30),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x38DDE6F4)),
        color: const Color(0x0ADDE6F4),
      ),
      child: Text(
        k,
        style: Tokens.body(
          size: 12,
          weight: FontWeight.w600,
          color: Tokens.text,
        ),
      ),
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: 22,
        runSpacing: 8,
        children: [
          for (final (keys, label) in hints)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...keys.map(key),
                const SizedBox(width: 4),
                Text(label, style: Tokens.body(size: 12, color: Tokens.muted)),
              ],
            ),
        ],
      ),
    );
  }
}
