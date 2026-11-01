import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// One row in an [OrbitOptionsSheet].
class OrbitSheetItem {
  const OrbitSheetItem({
    required this.label,
    required this.icon,
    this.value,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;

  /// Returned by [showOrbitOptionsSheet] when the row is chosen.
  final Object? value;

  /// Destructive rows are tinted danger and never take the safe focus.
  final bool danger;

  final bool enabled;
}

/// The Orbit options sheet: 560 wide, bottom aligned, Modal sheet elevation,
/// a 44×5 grab handle, a 22/600 title, a 14 muted subtitle and 54 px rows.
///
/// Prefer [showOrbitOptionsSheet], which adds the scrim, the 14 px rise and
/// returns the chosen value.
class OrbitOptionsSheet extends StatelessWidget {
  const OrbitOptionsSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    this.onSelected,
  });

  final String title;
  final String? subtitle;
  final List<OrbitSheetItem> items;

  /// Chosen row value. Defaults to popping the enclosing route when possible.
  final ValueChanged<Object?>? onSelected;

  static const double width = 560;

  void _select(BuildContext context, OrbitSheetItem item) {
    if (!item.enabled) return;
    final callback = onSelected;
    if (callback != null) {
      callback(item.value);
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop(item.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetWidth = math.min(width, MediaQuery.sizeOf(context).width - 16);
    var firstEnabled = items.indexWhere((item) => item.enabled);
    if (firstEnabled < 0) firstEnabled = 0;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: sheetWidth,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 78),
        decoration: Tokens.sheetDecor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Tokens.text.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.display(
                  size: 22,
                  weight: FontWeight.w600,
                  ls: 0,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(
                    size: 14,
                    color: Tokens.muted,
                    height: null,
                  ),
                ),
              )
            else
              const SizedBox(height: 10),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _SheetRow(
                item: items[i],
                autofocus: i == firstEnabled,
                onTap: () => _select(context, items[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatefulWidget {
  const _SheetRow({
    required this.item,
    required this.autofocus,
    required this.onTap,
  });

  final OrbitSheetItem item;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_SheetRow> createState() => _SheetRowState();
}

class _SheetRowState extends State<_SheetRow> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active = _focus || _hover;
    final foreground = !item.enabled
        ? Tokens.muted.withValues(alpha: 0.5)
        : item.danger
        ? Tokens.dangerText
        : active
        ? Colors.white
        : Tokens.text;
    final decoration = BoxDecoration(
      color: item.danger
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
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      border: item.danger ? Tokens.ringBorder : null,
      boxShadow: active ? Tokens.halo : null,
    );

    return Semantics(
      button: true,
      enabled: item.enabled,
      label: item.label,
      child: FocusableActionDetector(
        enabled: item.enabled,
        autofocus: widget.autofocus,
        mouseCursor: item.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onFocusChange: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (item.enabled) widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: item.enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            key: ValueKey('orbit-sheet-row-${item.label}'),
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: decoration,
            child: Row(
              children: [
                Icon(item.icon, size: 22, color: foreground),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 16,
                      weight: FontWeight.w600,
                      color: foreground,
                      height: null,
                    ),
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

/// Opens an [OrbitOptionsSheet] at the bottom of the screen, over a
/// rgba(2,7,13,.6) scrim. Returns the chosen [OrbitSheetItem.value], or null.
Future<T?> showOrbitOptionsSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<OrbitSheetItem> items,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss options',
    barrierColor: Tokens.scrim.withValues(alpha: 0.6),
    transitionDuration: Tokens.baseDur,
    pageBuilder: (dialogContext, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(dialogContext).maybePop(),
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FocusScope(
          autofocus: true,
          child: OrbitOptionsSheet(
            title: title,
            subtitle: subtitle,
            items: items,
            onSelected: (value) => Navigator.of(dialogContext).pop(value),
          ),
        ),
      ),
    ),
    transitionBuilder: (dialogContext, animation, _, child) {
      final reduce =
          MediaQuery.maybeDisableAnimationsOf(dialogContext) ?? false;
      final curved = CurvedAnimation(
        parent: animation,
        curve: reduce ? Curves.linear : Tokens.ease,
        reverseCurve: reduce ? Curves.linear : Tokens.easeInOut,
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
