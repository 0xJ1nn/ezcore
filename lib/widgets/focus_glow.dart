import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A tappable surface that shows where you are. Hover or focus lifts it a
/// little; keyboard or controller focus adds an electric-blue ring, so
/// navigating with a d-pad is always visible. Activates with tap, Enter,
/// Space, or a controller's A (through Flutter's ActivateIntent).
class FocusGlow extends StatefulWidget {
  const FocusGlow({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 14,
    this.lift = 1.03,
    this.semanticLabel,
    this.semanticHint,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;

  /// Scale while hovered or focused.
  final double lift;
  final String? semanticLabel;
  final String? semanticHint;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  bool _hover = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final active = _hover || _focus;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: active && !reduce ? widget.lift : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius + 3),
                border: Border.all(
                  color: _focus ? Tokens.accentHi : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: _focus
                    ? const [
                        BoxShadow(color: Color(0x66007BFF), blurRadius: 18),
                      ]
                    : const [],
              ),
              padding: const EdgeInsets.all(2),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
