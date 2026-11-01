import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// The Orbit toast: a 52 px pill at the bottom centre of the screen.
///
/// Visual only. Use [showOrbitToast] to insert one over the app; it owns the
/// 320 ms rise, the 2.6 s auto-hide (6 s while Undo is offered) and the
/// 200 ms in-out exit.
class OrbitToast extends StatelessWidget {
  const OrbitToast({
    super.key,
    required this.message,
    this.icon = Symbols.info,
    this.iconColor,
    this.onUndo,
    this.undoLabel = 'Undo',
    this.undoGlyph,
  });

  /// One line of 15/600 copy.
  final String message;

  /// Filled Material Symbol on the left.
  final IconData icon;
  final Color? iconColor;

  /// When set, the toast grows an Undo sub-pill and stays up for 6 s.
  final VoidCallback? onUndo;

  final String undoLabel;

  /// The input glyph shown inside Undo (for example "Y"); omitted when null.
  final String? undoGlyph;

  static const double height = 52;
  static const double radius = 26;

  bool get _hasUndo => onUndo != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: height,
          padding: EdgeInsets.only(left: 18, right: _hasUndo ? 10 : 18),
          decoration: BoxDecoration(
            color: Tokens.toastBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Tokens.lineStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                offset: const Offset(0, 20),
                blurRadius: 50,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: iconColor ?? Tokens.iconBlue,
                fill: 1,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(
                    size: 15,
                    weight: FontWeight.w600,
                    color: Colors.white,
                    height: null,
                  ),
                ),
              ),
              if (_hasUndo) ...[
                const SizedBox(width: 20),
                _UndoPill(label: undoLabel, glyph: undoGlyph, onTap: onUndo!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UndoPill extends StatelessWidget {
  const _UndoPill({
    required this.label,
    required this.glyph,
    required this.onTap,
  });

  final String label;
  final String? glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 8, right: 14),
            decoration: BoxDecoration(
              color: Tokens.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (glyph != null) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      glyph!,
                      style: Tokens.display(
                        size: 11,
                        weight: FontWeight.w700,
                        ls: 0,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Tokens.body(
                    size: 15,
                    weight: FontWeight.w600,
                    color: Colors.white,
                    height: null,
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

/// Handle returned by [showOrbitToast], so a screen can replace or dismiss a
/// toast before it hides itself.
class OrbitToastHandle {
  OrbitToastHandle._(this._stateKey);

  final GlobalKey<_OrbitToastLayerState> _stateKey;

  /// Removes the toast immediately (no exit animation).
  void dismiss() => _stateKey.currentState?._dismiss(immediate: true);
}

/// Shows [message] at the bottom centre of the nearest overlay.
///
/// The toast rises 14 px over 320 ms and hides after [duration] — 2.6 s by
/// default, 6 s when [onUndo] is supplied. Tapping Undo runs [onUndo] and
/// removes the toast.
OrbitToastHandle showOrbitToast(
  BuildContext context, {
  required String message,
  IconData icon = Symbols.info,
  Color? iconColor,
  VoidCallback? onUndo,
  String undoLabel = 'Undo',
  String? undoGlyph,
  Duration? duration,
  double bottom = 76,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final key = GlobalKey<_OrbitToastLayerState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _OrbitToastLayer(
      key: key,
      message: message,
      icon: icon,
      iconColor: iconColor,
      onUndo: onUndo,
      undoLabel: undoLabel,
      undoGlyph: undoGlyph,
      bottom: bottom,
      duration:
          duration ??
          (onUndo == null
              ? const Duration(milliseconds: 2600)
              : const Duration(seconds: 6)),
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
  return OrbitToastHandle._(key);
}

class _OrbitToastLayer extends StatefulWidget {
  const _OrbitToastLayer({
    super.key,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onUndo,
    required this.undoLabel,
    required this.undoGlyph,
    required this.bottom,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onUndo;
  final String undoLabel;
  final String? undoGlyph;
  final double bottom;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_OrbitToastLayer> createState() => _OrbitToastLayerState();
}

class _OrbitToastLayerState extends State<_OrbitToastLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _closing = false;

  bool get _reduceMotion => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _reduceMotion
          ? const Duration(milliseconds: 160)
          : Tokens.baseDur,
    )..forward();
    _timer = Timer(widget.duration, _hide);
  }

  Future<void> _hide() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  void _dismiss({bool immediate = false}) {
    if (_closing) return;
    if (immediate) {
      _closing = true;
      _timer?.cancel();
      widget.onDismissed();
      return;
    }
    unawaited(_hide());
  }

  void _undo() {
    widget.onUndo?.call();
    _dismiss(immediate: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: _reduceMotion ? Curves.linear : Tokens.ease,
      reverseCurve: _reduceMotion ? Curves.linear : Tokens.easeInOut,
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottom,
      child: Center(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = animation.value;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, _reduceMotion ? 0 : 14 * (1 - t)),
                child: child,
              ),
            );
          },
          child: OrbitToast(
            message: widget.message,
            icon: widget.icon,
            iconColor: widget.iconColor,
            onUndo: widget.onUndo == null ? null : _undo,
            undoLabel: widget.undoLabel,
            undoGlyph: widget.undoGlyph,
          ),
        ),
      ),
    );
  }
}
