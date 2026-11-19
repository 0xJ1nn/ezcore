import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'orbit_dialog.dart'
    show
        OrbitDialogAction,
        OrbitDialogActionKind,
        OrbitDialogTone,
        showOrbitDialog;

/// One way out of a blocked launch. The safe/default action is always first.
class LaunchErrorAction<T> {
  const LaunchErrorAction({
    required this.label,
    required this.value,
    this.primary = false,
  });

  final String label;
  final T value;
  final bool primary;
}

/// A blocked launch: missing core or missing BIOS (handoff §8.10).
///
/// Phones get a bottom sheet with stacked full-width buttons, exactly like
/// the device render; larger surfaces get the centred shake dialog. Neither
/// surface offers a download — the fix is always a file the reader owns or a
/// route to Systems.
Future<T?> showLaunchError<T>(
  BuildContext context, {
  required String title,
  required String body,
  IconData icon = Symbols.memory,
  required List<LaunchErrorAction<T>> actions,
}) {
  final phone =
      Layout.ofSize(MediaQuery.sizeOf(context), MediaQuery.orientationOf(context)) ==
      OrbitLayout.phonePortrait;
  if (!phone) {
    return showOrbitDialog<T>(
      context,
      title: title,
      body: body,
      icon: icon,
      tone: OrbitDialogTone.warn,
      error: true,
      actions: [
        for (final a in actions)
          OrbitDialogAction(
            label: a.label,
            value: a.value,
            kind: a.primary
                ? OrbitDialogActionKind.primary
                : OrbitDialogActionKind.secondary,
          ),
      ],
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss dialog',
    barrierColor: Tokens.scrim.withValues(alpha: 0.7),
    transitionDuration: Tokens.baseDur,
    pageBuilder: (ctx, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(ctx).maybePop(),
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FocusScope(
          autofocus: true,
          child: LaunchErrorSheet<T>(
            title: title,
            body: body,
            icon: icon,
            actions: actions,
            onSelected: (value) => Navigator.of(ctx).pop(value),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      final curved = CurvedAnimation(
        parent: animation,
        curve: reduce ? Curves.linear : Tokens.ease,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, reduce ? 0 : 14 * (1 - curved.value)),
            child: child,
          ),
        ),
        child: child,
      );
    },
  );
}

/// The phone's blocked-launch sheet: handle, warn icon, copy and stacked
/// full-width buttons. Public so a screen can embed it directly in tests.
class LaunchErrorSheet<T> extends StatelessWidget {
  const LaunchErrorSheet({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.actions,
    required this.onSelected,
  });

  final String title;
  final String body;
  final IconData icon;
  final List<LaunchErrorAction<T>> actions;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 27),
        decoration: Tokens.sheetDecor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Tokens.text.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(icon, size: 28, color: Tokens.warn, fill: 1),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Tokens.display(
                size: 24,
                weight: FontWeight.w600,
                ls: -0.02 * 24,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              body,
              style: Tokens.body(size: 14, color: Tokens.muted, height: 1.6),
            ),
            const SizedBox(height: 39),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _SheetButton(
                label: actions[i].label,
                primary: actions[i].primary,
                autofocus: i == 0,
                onTap: () => onSelected(actions[i].value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatefulWidget {
  const _SheetButton({
    required this.label,
    required this.primary,
    required this.autofocus,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_SheetButton> createState() => _SheetButtonState();
}

class _SheetButtonState extends State<_SheetButton> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        onFocusChange: (v) => setState(() => _focus = v),
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
            duration: Tokens.fastDur,
            height: 52,
            alignment: Alignment.center,
            decoration: widget.primary
                ? Tokens.primaryButton(
                    state: _focus
                        ? OrbitButtonState.hover
                        : OrbitButtonState.rest,
                  )
                : Tokens.secondaryButton(
                    state: _focus
                        ? OrbitButtonState.hover
                        : OrbitButtonState.rest,
                  ),
            child: Text(
              widget.label,
              style: Tokens.body(
                size: 15,
                weight: FontWeight.w700,
                color: widget.primary ? Colors.white : Tokens.text,
                height: null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
