import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/tokens.dart';
import '../cover_flow.dart' show balanceCoverTitle;
import '../orbit_widgets.dart' show GameCover;
import '../pad_navigator.dart' show FocusOwner;

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
    this.contentPresent = true,
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

  /// False for an entry whose file is gone and whose folder is still here;
  /// forwarded to [GameCover] so its stored art is withheld.
  final bool contentPresent;

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
            contentPresent: contentPresent,
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
///
/// It is still the same single focus as everywhere else: pointer hover *asks*
/// this node for focus, arrows and the d-pad move to it, and the ring, the lift
/// and a row-end edge bump all come from that one [FocusOwner].
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
  final FocusNode _node = FocusNode(debugLabel: 'look tile');
  bool _focused = false;
  double _edge = 0;
  Offset _edgeDirection = Offset.zero;
  Timer? _edgeTimer;

  String get _id => widget.semanticLabel ?? 'look-${_node.hashCode}';

  @override
  void initState() {
    super.initState();
    FocusOwner.shared.register(_id, _node);
    FocusOwner.shared.edge.addListener(_onEdge);
  }

  @override
  void didUpdateWidget(LookTile old) {
    super.didUpdateWidget(old);
    if (old.semanticLabel != widget.semanticLabel) {
      FocusOwner.shared.unregister(
        old.semanticLabel ?? 'look-${_node.hashCode}',
        _node,
      );
      FocusOwner.shared.register(_id, _node);
    }
  }

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
    // A pad-first layout has no hover states. Everywhere else a pointer moves
    // the one focus instead of painting a second highlight.
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
              scale: _focused && !reduce ? widget.lift : 1,
              duration: Tokens.instantDur,
              curve: Tokens.ease,
              child: AnimatedContainer(
                duration: Tokens.instantDur,
                curve: Tokens.ease,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  border: _focused
                      ? Border.all(color: Tokens.accentHi, width: 2)
                      : null,
                ),
                child: widget.child,
              ),
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
