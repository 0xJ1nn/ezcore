import 'dart:async';

import 'package:flutter/material.dart';

import '../brand/brand_mark.dart';
import '../services/gamepad.dart';
import '../state/input_mode.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// The OS bar across the top of every destination: the ezCORE lockup, the
/// line the brand stands on, and a status corner that only shows what is
/// true (the time, and a controller when one is connected).
class OrbitTopBar extends StatelessWidget {
  const OrbitTopBar({
    super.key,
    required this.compact,
    this.subscribeConnection,
  });

  /// Phones: the lockup alone (the system shows its own clock).
  final bool compact;

  /// Controller connection updates; defaults to the shared pad service.
  final void Function() Function(void Function(bool, String))?
  subscribeConnection;

  @override
  Widget build(BuildContext context) {
    if (compact) return const BrandLockup(height: 22);
    return Row(
      children: [
        const BrandLockup(height: 30),
        const Spacer(),
        OrbitStatus(subscribeConnection: subscribeConnection),
      ],
    );
  }
}

/// Live clock and controller badge.
class OrbitStatus extends StatefulWidget {
  const OrbitStatus({super.key, this.subscribeConnection, this.now});

  final void Function() Function(void Function(bool, String))?
  subscribeConnection;

  /// The clock source (tests pin it).
  final DateTime Function()? now;

  @override
  State<OrbitStatus> createState() => _OrbitStatusState();
}

class _OrbitStatusState extends State<OrbitStatus> {
  Timer? _tick;
  void Function()? _cancelPad;
  String? _pad;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _pad = GamepadService.shared.connectedPad;
    _cancelPad =
        (widget.subscribeConnection ?? GamepadService.shared.onConnection)((
          connected,
          name,
        ) {
          if (mounted) setState(() => _pad = connected ? name : null);
        });
    InputMode.shared.addListener(_onInputChanged);
    _schedule();
  }

  /// The status corner follows the last input on the very event that moves
  /// focus, so it never disagrees with the hint row (§4.1, §7.2).
  void _onInputChanged() {
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
    _cancelPad?.call();
    InputMode.shared.removeListener(_onInputChanged);
    super.dispose();
  }

  String get _inputLabel => switch (InputMode.shared.lastSource) {
    OrbitInputSource.keyboard => 'Keyboard',
    OrbitInputSource.pointer => 'Mouse',
    OrbitInputSource.pad => InputMode.shared.padName ?? 'Controller',
  };

  IconData get _inputIcon => switch (InputMode.shared.lastSource) {
    OrbitInputSource.keyboard => Symbols.keyboard,
    OrbitInputSource.pointer => Symbols.mouse,
    OrbitInputSource.pad => Symbols.gamepad,
  };

  @override
  Widget build(BuildContext context) {
    final t = _now();
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    // Narrow windows give the title and its tools the room they need; only
    // the clock stays in the status corner there, as the device frames show.
    final showLabels = MediaQuery.sizeOf(context).width >= Tokens.bpDesktop;
    if (!showLabels) {
      return Text(
        time,
        style: Tokens.display(
          size: 16,
          weight: FontWeight.w600,
          color: Tokens.text,
          height: 1,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusChip(
          icon: Symbols.lock,
          label: 'On this device',
          boxed: true,
        ),
        const SizedBox(width: 28),
        _StatusChip(icon: _inputIcon, label: _inputLabel),
        const SizedBox(width: 28),
        Text(
          time,
          style: Tokens.display(
            size: 16,
            weight: FontWeight.w600,
            color: Tokens.text,
            height: 1,
          ),
        ),
        if (_pad != null) ...[
          const SizedBox(width: 12),
          Tooltip(
            message: '$_pad connected',
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x14DDE6F4),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0x80007BFF)),
                boxShadow: const [
                  BoxShadow(color: Color(0x40007BFF), blurRadius: 12),
                ],
              ),
              child: Semantics(
                label: 'Controller connected: $_pad',
                child: Text(
                  'P1',
                  style: Tokens.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One item of the OS bar's status corner: an icon and a short, honest label.
/// "On this device" is the only boxed one; the input label sits on the scene,
/// exactly as the desktop reference draws it (§7.2).
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    this.boxed = false,
  });

  final IconData icon;
  final String label;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Tokens.muted),
        const SizedBox(width: 8),
        Text(
          label,
          style: Tokens.body(
            size: 13,
            weight: FontWeight.w500,
            color: Tokens.muted,
            height: 1,
          ),
        ),
      ],
    );
    if (!boxed) return child;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF16222F),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: child,
    );
  }
}

/// Keyboard hints along the foot of a screen: what each key does here.
class OrbitKeyHints extends StatelessWidget {
  const OrbitKeyHints({super.key, required this.hints, this.padHints});

  /// (keys, what they do).
  final List<(List<String>, String)> hints;

  /// Screen-specific pad glyphs, used instead of the defaults on pad-first
  /// families (for example the handheld's "L1△ System").
  final List<({String glyph, String label})>? padHints;

  @override
  Widget build(BuildContext context) {
    final modifier = Layout.modifierOf(context);
    if (Layout.showHintRow(modifier)) {
      return OrbitHintRow(
        modifier: modifier,
        hints:
            padHints ??
            const [
              (glyph: 'A', label: 'Resume'),
              (glyph: 'Y', label: 'Details'),
              (glyph: 'X', label: 'Options'),
              (glyph: 'CTRL', label: 'System'),
            ],
      );
    }
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

/// Applies the input-aware modifiers that affect *every* screen: the TV's
/// uniform 1.33 scale (which makes the 270 px shelf cover a 360 px one and
/// the 104 px rail a 136 px one) and the virtual viewport that goes with it.
///
/// Width-first modifiers (ultrawide's centred dock) and the safe area are
/// applied by the shell, because they depend on where the rail sits.
class InputAwareViewport extends StatelessWidget {
  const InputAwareViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outer = context
        .dependOnInheritedWidgetOfExactType<InputAwareViewportMarker>();
    if (outer != null) return child; // already measured by an ancestor
    final media = MediaQuery.of(context);
    final modifier = Layout.modifierOfSize(media.size, media.orientation);
    if (modifier != LayoutModifier.tv) {
      return InputAwareViewportMarker(modifier: modifier, child: child);
    }
    final scale = Layout.typeScale(modifier);
    final virtual = Size(media.size.width / scale, media.size.height / scale);
    return InputAwareViewportMarker(
      modifier: modifier,
      // A Transform is laid out by its parent, so a tight screen-sized
      // constraint would size the child to the physical window and then blow
      // it up again, pushing the right-hand third off screen. UnconstrainedBox
      // lets the virtual SizedBox choose its own size; the transform then
      // maps exactly that box onto the screen.
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: UnconstrainedBox(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: virtual.width,
            height: virtual.height,
            child: MediaQuery(
              data: media.copyWith(size: virtual),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The always-visible glyph hints on pad-first layouts (§7.4). There is no
/// mouse to discover hidden actions from across the room, so every action in
/// the current layer stays on screen.
class OrbitHintRow extends StatelessWidget {
  const OrbitHintRow({
    super.key,
    this.modifier = LayoutModifier.handheld,
    this.hints = const [
      (glyph: 'A', label: 'Resume'),
      (glyph: 'Y', label: 'Details'),
      (glyph: 'X', label: 'Options'),
      (glyph: 'CTRL', label: 'System'),
    ],
  });

  final LayoutModifier modifier;
  final List<({String glyph, String label})> hints;

  @override
  Widget build(BuildContext context) {
    final floor = Layout.textFloor(modifier);
    Widget chip(String glyph) => Container(
      constraints: BoxConstraints(minWidth: 26, minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x1ADDE6F4),
        borderRadius: BorderRadius.circular(13),
        border: const Border.fromBorderSide(
          BorderSide(color: Color(0x2BFFFFFF)),
        ),
      ),
      child: Text(
        glyph,
        style: Tokens.display(
          size: floor < 12 ? floor : 12,
          weight: FontWeight.w700,
        ),
      ),
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final hint in hints) ...[
            chip(hint.glyph),
            const SizedBox(width: 6),
            Text(
              hint.label,
              style: Tokens.body(
                size: floor < 14 ? floor : 14,
                weight: FontWeight.w600,
                color: Tokens.muted,
                height: null,
              ),
            ),
            const SizedBox(width: 24),
          ],
        ],
      ),
    );
  }
}
