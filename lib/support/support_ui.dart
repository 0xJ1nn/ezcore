// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'diamond_tokens.dart';

/// The bottom hint bar from the design: key cap + verb pairs.
class SupportHintBar extends StatelessWidget {
  const SupportHintBar({super.key, required this.hints});

  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (key, label) in hints) ...[
          const SizedBox(width: 22),
          Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 30),
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0x38FFFFFF)),
                ),
                child: Text(
                  key,
                  style: Tokens.display(
                    size: 11,
                    weight: FontWeight.w700,
                    ls: 0,
                    color: Tokens.text,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Tokens.body(
                  size: 15,
                  color: Tokens.muted,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A design button. [style] is pri / sec / dia.
class SupportButton extends StatelessWidget {
  const SupportButton({
    super.key,
    required this.label,
    this.icon,
    this.style = 'dia',
    this.onTap,
    this.width,
  });

  final String label;
  final IconData? icon;
  final String style;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final dia = style == 'dia';
    final pri = style == 'pri';
    final decoration = BoxDecoration(
      color: dia || pri ? null : Colors.transparent,
      gradient: dia ? DiamondTokens.buttonGradient : null,
      borderRadius: BorderRadius.circular(14),
      border: dia || pri
          ? null
          : Border.all(color: const Color(0x29FFFFFF)),
      boxShadow: dia
          ? const [
              BoxShadow(
                color: Color(0xE64DA3FF),
                offset: Offset(0, 12),
                blurRadius: 34,
                spreadRadius: -10,
              ),
            ]
          : pri
          ? const [
              BoxShadow(
                color: Color(0xCC007BFF),
                offset: Offset(0, 10),
                blurRadius: 30,
                spreadRadius: -10,
              ),
            ]
          : null,
    );
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: decoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Tokens.body(
                    size: 16,
                    weight: FontWeight.w700,
                    color: dia || pri ? Colors.white : Tokens.text,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps sheet content with the design's scrim and the bottom-rise transition.
/// Content widgets ([PlansSheet], [TipsSheet]) are plain widgets so captures
/// can render them without a dialog route.
Future<T?> showSupportSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x9E03060C), // rgba(3,6,12,.62)
    transitionDuration: Telemetry.sheetIn,
    pageBuilder: (ctx, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(ctx).maybePop(),
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Focus(
                autofocus: true,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).maybePop(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: builder(ctx)),
        ],
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      final curved = CurvedAnimation(
        parent: animation,
        curve: reduce ? Curves.linear : Tokens.ease,
        reverseCurve: Curves.linear,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, reduce ? 0 : 1 - curved.value),
          child: Opacity(opacity: curved.value, child: child),
        ),
        child: child,
      );
    },
  );
}

/// The sheet container: phone full width / desktop 760, 28 / 24 top radius.
class SupportSheetFrame extends StatelessWidget {
  const SupportSheetFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(36, 14, 36, 30),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    final maxHeight = MediaQuery.sizeOf(context).height - 16;
    return Container(
      width: phone ? double.infinity : 760,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: phone
          ? const EdgeInsets.fromLTRB(20, 12, 20, 34)
          : padding,
      decoration: BoxDecoration(
        color: DiamondTokens.sheet,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(phone ? 28 : 24),
        ),
        border: const Border(
          top: BorderSide(color: Color(0x1AFFFFFF)),
          left: BorderSide(color: Color(0x1AFFFFFF)),
          right: BorderSide(color: Color(0x1AFFFFFF)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0xCC000000),
            offset: Offset(0, -30),
            blurRadius: 80,
            spreadRadius: -20,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: EdgeInsets.only(bottom: phone ? 16 : 20),
                decoration: BoxDecoration(
                  color: const Color(0x38FFFFFF),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Motion values from the design's Spec block, surfaced as named constants.
abstract final class Telemetry {
  static const Duration sheetIn = Duration(milliseconds: 420);
  static const Duration sheetOut = Duration(milliseconds: 280);
  static const Duration scrimIn = Duration(milliseconds: 240);
  static const Duration tipFocus = Duration(milliseconds: 180);
  static const Duration thanksPop = Duration(milliseconds: 700);
  static const Duration thanksAutoDismiss = Duration(seconds: 4);
}

/// The four purchase toasts from frame 7, expressed as copy + icon + colour.
class SupportToasts {
  static const pending = (
    'Waiting for approval. You can keep playing.',
    Symbols.hourglassTop,
  );
  static const failed = (
    "The purchase didn't go through. You weren't charged.",
    Symbols.error,
  );
  static const restored = (
    'Diamond restored on this device.',
    Symbols.checkCircle,
  );
  static const nothing = (
    'No purchases to restore for this account.',
    Symbols.info,
  );
}
