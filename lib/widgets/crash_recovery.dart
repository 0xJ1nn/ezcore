// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// What the reader chose after a core stopped unexpectedly.
enum CrashRecoveryChoice { resume, back }

/// The "game stopped unexpectedly" dialog (Devices 4e): plain about what
/// happened, and recovery as the first action. A crash-safe snapshot is
/// offered from the time capsule; nothing implies the game was paused.
class CrashRecoveryDialog extends StatelessWidget {
  const CrashRecoveryDialog({
    super.key,
    required this.gameTitle,
    this.onSelected,
  });

  final String gameTitle;
  final ValueChanged<CrashRecoveryChoice>? onSelected;

  static const _body =
      'Crash protection kept ezCORE running. A snapshot from 40 seconds '
      'before the stop is safe in your time capsule.';
  static const _note =
      'If this keeps happening, try another core for this system.';

  void _choose(BuildContext context, CrashRecoveryChoice choice) {
    final callback = onSelected;
    if (callback != null) {
      callback(choice);
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop(choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        container: true,
        child: Container(
          width: 480,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          decoration: Tokens.dialogDecor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.extension, size: 22, color: Tokens.warn),
              const SizedBox(height: 12),
              Text(
                '$gameTitle stopped unexpectedly',
                style: Tokens.display(
                  size: 22,
                  weight: FontWeight.w600,
                  ls: -0.02 * 22,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                _body,
                style: TextStyle(
                  fontFamily: Tokens.bodyFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Tokens.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                children: [
                  _ChoiceButton(
                    label: 'Resume from snapshot',
                    icon: Symbols.playArrow,
                    primary: true,
                    onTap: () => _choose(context, CrashRecoveryChoice.resume),
                  ),
                  _ChoiceButton(
                    label: 'Back to library',
                    primary: false,
                    onTap: () => _choose(context, CrashRecoveryChoice.back),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                _note,
                style: TextStyle(
                  fontFamily: Tokens.bodyFamily,
                  fontSize: 12,
                  color: Tokens.separator,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatefulWidget {
  const _ChoiceButton({
    required this.label,
    required this.primary,
    this.icon,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.primary
        ? OrbitButtonState.hover
        : OrbitButtonState.rest;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        autofocus: widget.primary,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
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
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: widget.primary
                ? Tokens.primaryButton(
                    state: _hover ? OrbitButtonState.hover : kind,
                  )
                : Tokens.secondaryButton(
                    state: _hover ? OrbitButtonState.hover : OrbitButtonState.rest,
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: Tokens.body(
                    size: 14,
                    weight: FontWeight.w700,
                    color: widget.primary ? Colors.white : Tokens.text,
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

/// Shows the dialog over a frozen, desaturated stage. The frame behind stops
/// moving (the player's own animation is not restarted) and reads as stopped
/// rather than paused. Returns the chosen recovery action.
Future<CrashRecoveryChoice?> showCrashRecovery(
  BuildContext context, {
  required String gameTitle,
}) {
  return showGeneralDialog<CrashRecoveryChoice>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Dismiss crash dialog',
    barrierColor: Tokens.scrim.withValues(alpha: 0.9),
    transitionDuration: Tokens.baseDur,
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.matrix(Float64List.fromList(const <double>[
              0.2126, 0.7152, 0.0722, 0, //
              0.2126, 0.7152, 0.0722, 0,
              0.2126, 0.7152, 0.0722, 0,
              0, 0, 0, 1,
            ])),
            child: const SizedBox.expand(),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FocusScope(
              autofocus: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: CrashRecoveryDialog(gameTitle: gameTitle),
              ),
            ),
          ),
        ),
      ],
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
          child: Transform.scale(
            scale: reduce ? 1 : 0.97 + 0.03 * curved.value,
            child: child,
          ),
        ),
        child: child,
      );
    },
  );
}
