// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';
import 'pad_navigator.dart';

/// A tappable surface that shows where you are.
///
/// Hover, keyboard and d-pad all write to the one [FocusOwner], so this widget
/// has a single focus state rather than a separate hover state: the ring and
/// the lift appear only on the element that actually owns the focus. Activating
/// works with tap, Enter, Space, or a controller's A (ActivateIntent).
class FocusGlow extends StatefulWidget {
  const FocusGlow({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 14,
    this.lift = 1.03,
    this.semanticLabel,
    this.semanticHint,
    this.focusId,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;

  /// Scale while focused.
  final double lift;
  final String? semanticLabel;
  final String? semanticHint;

  /// Stable id used to remember this control per screen and to aim an edge
  /// bump at it. Defaults to the semantic label so callers need no extra work.
  final String? focusId;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  final FocusNode _node = FocusNode(debugLabel: 'focus glow');
  bool _focused = false;
  double _edge = 0;
  Offset _edgeDirection = Offset.zero;
  Timer? _edgeTimer;

  String get _id =>
      widget.focusId ?? widget.semanticLabel ?? 'focus-${_node.hashCode}';

  @override
  void initState() {
    super.initState();
    FocusOwner.shared.register(_id, _node);
    FocusOwner.shared.edge.addListener(_onEdge);
  }

  @override
  void didUpdateWidget(FocusGlow old) {
    super.didUpdateWidget(old);
    if (old.focusId != widget.focusId || old.semanticLabel != widget.semanticLabel) {
      FocusOwner.shared.unregister(_idOf(old), _node);
      FocusOwner.shared.register(_id, _node);
    }
  }

  String _idOf(FocusGlow w) =>
      w.focusId ?? w.semanticLabel ?? 'focus-${_node.hashCode}';

  @override
  void dispose() {
    FocusOwner.shared.edge.removeListener(_onEdge);
    FocusOwner.shared.unregister(_id, _node);
    _edgeTimer?.cancel();
    _node.dispose();
    super.dispose();
  }

  void _onEdge() {
    final signal = FocusOwner.shared.edge.value;
    if (signal == null || signal.id != _id || !mounted) return;
    _edgeDirection = switch (signal.direction) {
      TraversalDirection.left => const Offset(-1, 0),
      TraversalDirection.right => const Offset(1, 0),
      TraversalDirection.up => const Offset(0, -1),
      TraversalDirection.down => const Offset(0, 1),
    };
    _edgeTimer?.cancel();
    setState(() => _edge = FocusOwner.edgeNudge);
    _edgeTimer = Timer(FocusOwner.edgeDuration, () {
      if (!mounted) return;
      setState(() => _edge = 0);
    });
  }

  void _onHover(bool hovering) {
    // A pad-first layout has no hover states; everywhere else a pointer moves
    // the single focus instead of painting a second highlight.
    if (hovering && Layout.showHover(Layout.modifierOf(context))) {
      FocusOwner.shared.stopRepeat();
      _node.requestFocus();
    }
  }

  void _activate() {
    _node.requestFocus();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final active = _focused; // one source: the node that owns the focus
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      child: FocusableActionDetector(
        focusNode: _node,
        onFocusChange: (focused) {
          if (!mounted) return;
          setState(() => _focused = focused);
          if (focused) FocusOwner.shared.remember(_node);
        },
        onShowHoverHighlight: _onHover,
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: _activate,
          behavior: HitTestBehavior.opaque,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: reduce ? 0 : _edge),
            duration: FocusOwner.edgeDuration,
            curve: Tokens.ease,
            builder: (context, offset, child) => Transform.translate(
              offset: _edgeDirection * offset,
              child: child,
            ),
            child: AnimatedScale(
              scale: active && !reduce ? widget.lift : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius + 3),
                  border: Border.all(
                    color: active ? Tokens.accentHi : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: active
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
      ),
    );
  }
}
