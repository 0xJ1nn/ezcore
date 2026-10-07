import 'dart:async';

import 'package:flutter/material.dart';

import '../brand/brand_mark.dart';
import '../services/gamepad.dart';
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
    return LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          const BrandLockup(height: 30),
          const Spacer(),
          if (c.maxWidth >= 860) ...[
            Text(
              Tokens.taglineMain,
              style: Tokens.body(
                size: 10.5,
                weight: FontWeight.w600,
                ls: 4.2,
                color: Tokens.muted,
              ),
            ),
            const SizedBox(width: 28),
          ],
          OrbitStatus(subscribeConnection: subscribeConnection),
        ],
      ),
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
    _schedule();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _now();
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: Tokens.body(
            size: 13,
            weight: FontWeight.w600,
            color: Tokens.text,
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
