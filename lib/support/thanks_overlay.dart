import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'diamond_tokens.dart';
import 'support_ui.dart';
import 'tips_sheet.dart';

String _titleFor(String productId) {
  for (final (id, name, _) in tipItems) {
    if (id == productId) return name;
  }
  return 'tip';
}

/// "3 coffees and 2 pizzas", from the device-only tip tally.
String describeTally(Map<String, int> tally) {
  final parts = <String>[];
  for (final (id, name, _) in tipItems) {
    final count = tally[id] ?? 0;
    if (count > 0) {
      final word = name.toLowerCase();
      parts.add('$count ${count == 1 ? word : '${word}s'}');
    }
  }
  if (parts.isEmpty) return 'You have not sent a tip yet.';
  if (parts.length == 1) return 'You have sent ${parts.first}.';
  return 'You have sent ${parts.take(parts.length - 1).join(', ')} '
      'and ${parts.last}.';
}

/// The thank-you overlay (design frame 4): plate pop, copy fade, 4 s auto
/// dismiss or Done. Only the tip tally, never a server, is involved.
class ThanksOverlay extends StatefulWidget {
  const ThanksOverlay({
    super.key,
    required this.productId,
    required this.tally,
    this.onDone,
    this.autoDismiss = true,
  });

  final String productId;
  final Map<String, int> tally;
  final VoidCallback? onDone;
  final bool autoDismiss;

  @override
  State<ThanksOverlay> createState() => _ThanksOverlayState();
}

class _ThanksOverlayState extends State<ThanksOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Telemetry.thanksPop,
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoDismiss) {
      _timer = Timer(Telemetry.thanksAutoDismiss, _done);
    }
  }

  void _done() {
    _timer?.cancel();
    final done = widget.onDone;
    if (done != null) {
      done();
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final curved = CurvedAnimation(parent: _controller, curve: Tokens.ease);
    final name = _titleFor(widget.productId).toLowerCase();
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Color(0xD603060C)),
          ),
          Center(
            child: SizedBox(
              width: 560,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): _done,
                  const SingleActivator(LogicalKeyboardKey.select): _done,
                  const SingleActivator(LogicalKeyboardKey.escape): _done,
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: curved,
                      builder: (context, child) {
                        final t = reduce ? 1.0 : curved.value;
                        final scale = t < 0.6
                            ? 0.6 + (0.46 * (t / 0.6))
                            : 1.06 - (0.06 * ((t - 0.6) / 0.4));
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Container(
                        width: 148,
                        height: 148,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          gradient: const RadialGradient(
                            center: Alignment(0, -0.3),
                            colors: [Color(0x614DA3FF), Color(0x0F4DA3FF)],
                          ),
                          border: Border.all(color: const Color(0x59A8CEFF)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x994DA3FF),
                              blurRadius: 60,
                              spreadRadius: -10,
                            ),
                          ],
                        ),
                        child: Icon(
                          Symbols.localPizza,
                          size: 84,
                          color: DiamondTokens.fg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Thanks for the $name.',
                      textAlign: TextAlign.center,
                      style: Tokens.display(
                        size: 40,
                        weight: FontWeight.w600,
                        ls: -0.03 * 40,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      describeTally(widget.tally),
                      textAlign: TextAlign.center,
                      style: Tokens.body(
                        size: 16,
                        color: Tokens.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 26),
                    SupportButton(
                      label: 'Done',
                      style: 'sec',
                      width: 200,
                      onTap: _done,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showThanksOverlay(
  BuildContext context, {
  required String productId,
  required Map<String, int> tally,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Done',
    barrierColor: Colors.transparent,
    transitionDuration: Tokens.baseDur,
    pageBuilder: (ctx, _, _) => ThanksOverlay(
      productId: productId,
      tally: tally,
    ),
  );
}
