import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../cover_flow.dart' show balanceCoverTitle;
import '../orbit_widgets.dart' show GameCover;

/// A generated cover with the library's selected outline on top.
///
/// All four looks use the same [GameCover] component the 3D shelf and the
/// detail page use, so a screenshot the player pins shows up everywhere. Only
/// the outline belongs to the look itself.
class LibraryCover extends StatelessWidget {
  const LibraryCover({
    super.key,
    required this.gameId,
    required this.title,
    required this.systemId,
    this.year,
    this.favorite = false,
    this.badgeText,
    this.badgeColor,
    this.width,
    this.height,
    this.radius = Tokens.radiusCover,
    this.selected = false,
    this.dimmed = false,
  });

  final String gameId;
  final String title;
  final String systemId;
  final int? year;
  final bool favorite;
  final String? badgeText;
  final Color? badgeColor;
  final double? width;
  final double? height;
  final double radius;
  final bool selected;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GameCover(
            gameId: gameId,
            title: title,
            systemId: systemId,
            year: year,
            favorite: favorite,
            badgeText: badgeText,
            badgeColor: badgeColor,
            radius: radius,
            dimmed: dimmed,
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: Tokens.accentHi, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A focusable tile with no layout padding. [FocusGlow] reserves 2 px of
/// padding and a 2.5 px border around its child, which would shrink a measured
/// 132×176 grid cover to 123×167. The measured looks need the cover to be the
/// whole tile, so this variant paints its focus ring inside the same box.
class LookTile extends StatefulWidget {
  const LookTile({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = Tokens.radiusCover,
    this.semanticLabel,
    this.semanticHint,
    this.lift = 1.02,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;
  final String? semanticLabel;
  final String? semanticHint;
  final double lift;

  @override
  State<LookTile> createState() => _LookTileState();
}

class _LookTileState extends State<LookTile> {
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
            duration: Tokens.instantDur,
            curve: Tokens.ease,
            child: AnimatedContainer(
              duration: Tokens.instantDur,
              curve: Tokens.ease,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: _focus
                    ? Border.all(color: Tokens.accentHi, width: 2)
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cover titles are balanced across lines, so every look wraps them the same
/// way the 3D shelf does.
String libraryCoverTitle(String title, {double coverWidth = 270}) =>
    balanceCoverTitle(title, coverWidth: coverWidth);
