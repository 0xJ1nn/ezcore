import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// The tone of a dialog's 34 px icon.
enum OrbitDialogTone { info, warn, danger }

/// A dialog button's visual role.
enum OrbitDialogActionKind { primary, secondary, danger }

/// One action in an [OrbitDialog].
class OrbitDialogAction {
  const OrbitDialogAction({
    required this.label,
    this.value,
    this.kind = OrbitDialogActionKind.secondary,
    this.glyph,
  });

  final String label;

  /// Returned by [showOrbitDialog] when this action is chosen.
  final Object? value;

  final OrbitDialogActionKind kind;

  /// Optional input glyph shown before the label.
  final String? glyph;
}

/// The Orbit modal dialog: 600 wide, 34 padding, r22, Modal elevation.
///
/// The first non-danger action is focused when the dialog opens, so a
/// destructive confirm never opens on its destructive button. Error variants
/// shake −10, 8, −5, 3 px over 360 ms. Prefer [showOrbitDialog] or
/// [showOrbitConfirmDialog], which add the scrim and return the chosen value.
class OrbitDialog extends StatefulWidget {
  const OrbitDialog({
    super.key,
    required this.title,
    required this.body,
    this.icon = Symbols.info,
    this.tone = OrbitDialogTone.info,
    this.actions = const [],
    this.onSelected,
    this.error = false,
    this.animate = true,
  });

  final String title;
  final String body;
  final IconData icon;
  final OrbitDialogTone tone;
  final List<OrbitDialogAction> actions;

  /// Chosen action value. Defaults to popping the enclosing route when one
  /// can be popped.
  final ValueChanged<Object?>? onSelected;

  /// Shake instead of rising in.
  final bool error;

  /// Turn off for a static capture or a reduced-motion layout.
  final bool animate;

  static const double width = 600;
  static const double padding = 34;

  @override
  State<OrbitDialog> createState() => _OrbitDialogState();
}

class _OrbitDialogState extends State<OrbitDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.error
          ? const Duration(milliseconds: 360)
          : Tokens.baseDur,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose(Object? value) {
    final callback = widget.onSelected;
    if (callback != null) {
      callback(value);
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final width = math.min(
      OrbitDialog.width,
      MediaQuery.sizeOf(context).width - 32,
    );
    final iconColor = switch (widget.tone) {
      OrbitDialogTone.info => Tokens.iconBlue,
      OrbitDialogTone.warn => Tokens.warn,
      OrbitDialogTone.danger => Tokens.dangerText,
    };
    final safeIndex = widget.actions.indexWhere(
      (action) => action.kind != OrbitDialogActionKind.danger,
    );
    final firstFocus = safeIndex < 0 ? 0 : safeIndex;

    final content = Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(OrbitDialog.padding),
        decoration: Tokens.dialogDecor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(widget.icon, size: 34, color: iconColor, fill: 1),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: Tokens.displayDialog.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              widget.body,
              style: Tokens.bodyLead.copyWith(color: Tokens.muted),
            ),
            if (widget.actions.isNotEmpty) ...[
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < widget.actions.length; i++)
                    _DialogButton(
                      action: widget.actions[i],
                      autofocus: i == firstFocus,
                      onTap: () => _choose(widget.actions[i].value),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (reduce || !widget.animate) return content;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final eased = Tokens.ease.transform(t);
        final rise = widget.error ? 0.0 : 14 * (1 - eased);
        final opacity = widget.error ? 1.0 : eased;
        final dx = widget.error ? _shake(t) : 0.0;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(dx, rise), child: child),
        );
      },
      child: content,
    );
  }

  /// CSS `ez-shake`: 0 → −10 → 8 → −5 → 3 → 0, easing each segment.
  double _shake(double t) {
    const points = <double>[0, -10, 8, -5, 3, 0];
    final scaled = (t * 5).clamp(0.0, 5.0);
    final index = scaled.floor().clamp(0, 4);
    final local = Tokens.ease.transform(scaled - index);
    return lerpDouble(points[index], points[index + 1], local)!;
  }
}

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.action,
    required this.autofocus,
    required this.onTap,
  });

  final OrbitDialogAction action;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final active = _focus || _hover;
    final primary = a.kind == OrbitDialogActionKind.primary;
    final danger = a.kind == OrbitDialogActionKind.danger;
    final decoration = primary
        ? Tokens.primaryButton(
            state: active ? OrbitButtonState.hover : OrbitButtonState.rest,
          )
        : BoxDecoration(
            color: danger
                ? active
                      ? Color.alphaBlend(
                          Tokens.danger.withValues(alpha: 0.2),
                          Tokens.toastBg,
                        )
                      : Tokens.danger.withValues(alpha: 0.08)
                : active
                ? Color.alphaBlend(
                    Tokens.text.withValues(alpha: 0.14),
                    Tokens.toastBg,
                  )
                : Tokens.text.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
            border: Tokens.ringBorder,
            boxShadow: active ? Tokens.halo : null,
          );
    final foreground = primary
        ? Colors.white
        : danger
        ? Tokens.dangerText
        : Tokens.text;

    return Semantics(
      button: true,
      label: a.label,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
        onFocusChange: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
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
          child: AnimatedContainer(
            key: ValueKey('orbit-dialog-action-${a.label}'),
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (a.glyph != null) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      a.glyph!,
                      style: Tokens.display(
                        size: 12,
                        weight: FontWeight.w700,
                        ls: 0,
                        color: foreground,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  a.label,
                  style: Tokens.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: foreground,
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

/// Opens an [OrbitDialog] over the current route and returns the chosen
/// [OrbitDialogAction.value] (or null when dismissed).
Future<T?> showOrbitDialog<T>(
  BuildContext context, {
  required String title,
  required String body,
  required List<OrbitDialogAction> actions,
  IconData icon = Symbols.info,
  OrbitDialogTone tone = OrbitDialogTone.info,
  bool error = false,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss dialog',
    barrierColor: Tokens.scrim.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 1),
    pageBuilder: (dialogContext, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(dialogContext).maybePop(),
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FocusScope(
            autofocus: true,
            child: OrbitDialog(
              title: title,
              body: body,
              icon: icon,
              tone: tone,
              actions: actions,
              error: error,
              onSelected: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A confirm dialog with the **safe** choice focused first. Returns true only
/// when the confirm action is chosen.
Future<bool> showOrbitConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Remove',
  String cancelLabel = 'Keep it',
  bool danger = true,
  IconData icon = Symbols.delete,
  OrbitDialogTone? tone,
  bool error = false,
}) async {
  final result = await showOrbitDialog<bool>(
    context,
    title: title,
    body: body,
    icon: icon,
    tone: tone ?? (danger ? OrbitDialogTone.danger : OrbitDialogTone.info),
    error: error,
    actions: [
      OrbitDialogAction(
        label: cancelLabel,
        value: false,
        kind: OrbitDialogActionKind.secondary,
      ),
      OrbitDialogAction(
        label: confirmLabel,
        value: true,
        kind: danger
            ? OrbitDialogActionKind.danger
            : OrbitDialogActionKind.primary,
      ),
    ],
  );
  return result ?? false;
}

/// The error variant: danger icon and tone, a 360 ms shake, one way out.
Future<void> showOrbitErrorDialog(
  BuildContext context, {
  required String title,
  required String body,
  IconData icon = Symbols.error,
  String label = 'Got it',
}) {
  return showOrbitDialog<void>(
    context,
    title: title,
    body: body,
    icon: icon,
    tone: OrbitDialogTone.danger,
    error: true,
    actions: [
      OrbitDialogAction(label: label, kind: OrbitDialogActionKind.primary),
    ],
  );
}
