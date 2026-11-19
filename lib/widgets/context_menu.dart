import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// One row of the pointer menu (handoff 4d). The shortcut is printed so a
/// mouse user learns the keyboard route to the same action.
class ContextMenuItem<T> {
  const ContextMenuItem({
    required this.label,
    required this.icon,
    required this.value,
    this.shortcut,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final T value;
  final String? shortcut;
  final bool danger;
}

/// The same actions as the options sheet, drawn at the pointer on a right
/// click instead of as a bottom sheet on a long press.
class ContextMenu<T> extends StatelessWidget {
  const ContextMenu({super.key, required this.items, this.onSelected});

  final List<ContextMenuItem<T>> items;
  final ValueChanged<T>? onSelected;

  static const rowHeight = 42.0;
  static const width = 264.0;

  static double heightFor(int count) =>
      count * rowHeight + math.max(0, count - 1) + 12;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Tokens.toastBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tokens.lineStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              offset: Offset(0, 18),
              blurRadius: 42,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Container(height: 1, color: Tokens.line),
                ),
              _ContextRow(
                item: items[i],
                autofocus: i == 0,
                onTap: () => onSelected?.call(items[i].value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContextRow<T> extends StatefulWidget {
  const _ContextRow({
    required this.item,
    required this.autofocus,
    required this.onTap,
  });

  final ContextMenuItem<T> item;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_ContextRow<T>> createState() => _ContextRowState<T>();
}

class _ContextRowState<T> extends State<_ContextRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = item.danger
        ? Tokens.dangerText
        : _hover
        ? Colors.white
        : Tokens.text;
    return Semantics(
      button: true,
      label: item.shortcut == null
          ? item.label
          : '${item.label}, ${item.shortcut}',
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
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
          child: Container(
            height: ContextMenu.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _hover ? Tokens.text.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: color,
                      height: null,
                    ),
                  ),
                ),
                if (item.shortcut != null)
                  Text(
                    item.shortcut!,
                    style: Tokens.body(
                      size: 12,
                      color: Tokens.separator,
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

/// Opens the pointer menu at [at], clamped inside the viewport. No scrim: the
/// covers stay visible behind it, as in the device render.
Future<T?> showContextMenuAt<T>(
  BuildContext context,
  Offset at, {
  required List<ContextMenuItem<T>> items,
}) {
  final size = MediaQuery.sizeOf(context);
  final h = ContextMenu.heightFor(items.length);
  final left = at.dx
      .clamp(8.0, math.max(8.0, size.width - ContextMenu.width - 8))
      .toDouble();
  final top = at.dy.clamp(8.0, math.max(8.0, size.height - h - 8)).toDouble();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss menu',
    barrierColor: Colors.transparent,
    transitionDuration: Tokens.instantDur,
    pageBuilder: (ctx, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(ctx).maybePop(),
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: ContextMenu<T>(
              items: items,
              onSelected: (value) => Navigator.of(ctx).pop(value),
            ),
          ),
        ],
      ),
    ),
  );
}
