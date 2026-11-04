import 'package:flutter/material.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// How much of the game dock fits in the space the library has left.
enum GameDockMode {
  /// 1440×900: badge + meta, 32 px title, last-played line and four controls
  /// in a 132 px glass panel (§7.5).
  full,

  /// Landscape phones and tablets: one 76 px line — title and sub on the left,
  /// the actions on the right.
  oneLine,

  /// Portrait phones: the panel sits under the cover, so the actions get their
  /// own row at thumb height.
  stacked,

  /// Tiny windows: one line, title and the two essential actions.
  mini,
}

/// The selected game's dock (§7.5): what it is, when it was last played, and
/// the four things you can do with it — favourite, Resume, Details and More.
///
/// The dock is purely presentational; the library owns selection, launching
/// and the options sheet, so a tap always goes through one owner.
class GameDock extends StatelessWidget {
  const GameDock({
    super.key,
    required this.game,
    required this.mode,
    required this.onResume,
    required this.onDetails,
    required this.onFavorite,
    required this.onMore,
    this.height,
    this.padding,
    this.glyphConfirm = 'Enter',
    this.glyphDetails = 'E',
    this.showMeta = true,
    this.showStatus = true,
    this.showBadgeOnOneLine = false,
  });

  final GameEntry game;
  final GameDockMode mode;
  final VoidCallback onResume;
  final VoidCallback onDetails;
  final VoidCallback onFavorite;
  final VoidCallback onMore;

  /// Overrides the mode's natural height (the 132 px desktop panel).
  final double? height;
  final EdgeInsets? padding;

  /// Glyph chips follow the last input (§4.3); the library passes the current
  /// set, the defaults are the keyboard's.
  final String glyphConfirm;
  final String glyphDetails;

  final bool showMeta;
  final bool showStatus;

  /// The one-line dock usually names the system in its sub-line; a tablet
  /// portrait dock has the badge above the title instead (§10, frame 1c).
  final bool showBadgeOnOneLine;

  bool get _played => game.lastPlayedMs > 0;

  String get resumeLabel => _played ? 'Resume' : 'Play';

  String get _meta {
    final year = game.year;
    final size = fileSizeLabel(game.fileSize);
    if (year == null) return size;
    return '$year · $size';
  }

  String get _status {
    if (!_played) return 'Not played yet · ready when you are';
    return 'Last played ${lastPlayedLabel(game.lastPlayedMs).toLowerCase()} '
        '· picks up where you left off';
  }

  @override
  Widget build(BuildContext context) {
    final height =
        this.height ??
        switch (mode) {
          GameDockMode.full => 132.0,
          GameDockMode.oneLine => 76.0,
          GameDockMode.stacked => 154.0,
          GameDockMode.mini => 52.0,
        };
    final buttonSize = mode == GameDockMode.full ? 56.0 : 48.0;
    final pad =
        padding ??
        switch (mode) {
          GameDockMode.full => const EdgeInsets.fromLTRB(32, 18, 28, 18),
          GameDockMode.oneLine => const EdgeInsets.fromLTRB(24, 12, 20, 12),
          GameDockMode.stacked => const EdgeInsets.fromLTRB(16, 16, 16, 16),
          GameDockMode.mini => const EdgeInsets.symmetric(horizontal: 10),
        };
    return Container(
      height: height,
      padding: pad,
      // The glass surface from §3.5. A uniform ring keeps the radius legal;
      // the brighter top hairline is painted by the inner gradient.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusDock),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF21B2430), Color(0xF20B111B)],
          stops: [0.0, 0.7],
        ),
        border: Border.all(color: Tokens.lineStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x7A000000),
            offset: Offset(0, 18),
            blurRadius: 42,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _content(mode, buttonSize, constraints.maxWidth),
      ),
    );
  }

  Widget _content(GameDockMode mode, double buttonSize, double width) {
    if (mode == GameDockMode.mini) {
      return Row(
        children: [
          Expanded(
            child: Text(
              game.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tokens.body(
                size: 13,
                weight: FontWeight.w600,
                height: null,
              ),
            ),
          ),
          _DockAction(
            size: 38,
            primary: true,
            tooltip: resumeLabel,
            semanticLabel: resumeLabel,
            onPressed: onResume,
            child: const Icon(
              Symbols.playArrow,
              size: 17,
              color: Colors.white,
              fill: 1,
            ),
          ),
          const SizedBox(width: 8),
          _DockAction(
            size: 38,
            tooltip: 'More options',
            semanticLabel: 'More options',
            onPressed: onMore,
            child: const Icon(Symbols.moreHoriz, size: 18, color: Tokens.text),
          ),
        ],
      );
    }
    final info = _Info(
      game: game,
      mode: mode,
      meta: _meta,
      status: _status,
      showMeta: showMeta,
      showStatus: showStatus,
      showBadge: showBadgeOnOneLine,
    );
    final heart = _DockAction(
      size: buttonSize,
      tooltip: game.favorite ? 'Remove from favorites' : 'Add to favorites',
      semanticLabel: game.favorite
          ? 'Remove from favorites'
          : 'Add to favorites',
      onPressed: onFavorite,
      child: Icon(
        Symbols.favorite,
        size: 22,
        color: Tokens.text,
        fill: game.favorite ? 1 : 0,
      ),
    );
    final more = _DockAction(
      size: buttonSize,
      tooltip: 'More options',
      semanticLabel: 'More options',
      onPressed: onMore,
      child: const Icon(Symbols.moreHoriz, size: 22, color: Tokens.text),
    );

    final Widget actions;
    switch (mode) {
      case GameDockMode.full:
        actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            heart,
            const SizedBox(width: 10),
            _DockPrimary(
              label: resumeLabel,
              glyph: glyphConfirm,
              onPressed: onResume,
            ),
            const SizedBox(width: 10),
            _DockAction(
              size: buttonSize,
              tooltip: 'Details and snapshots',
              semanticLabel: 'Details and snapshots',
              onPressed: onDetails,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlyphChip(glyphDetails, onPrimary: false),
                  const SizedBox(width: 10),
                  const Icon(Symbols.info, size: 20, color: Tokens.text),
                  const SizedBox(width: 8),
                  Text(
                    'Details',
                    style: Tokens.body(
                      size: 16,
                      weight: FontWeight.w700,
                      color: Tokens.text,
                      height: null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            more,
          ],
        );
      case GameDockMode.oneLine:
        final showHeart = width >= 470;
        final showDetails = width >= 700;
        actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeart) ...[heart, const SizedBox(width: 10)],
            _DockPrimary(
              label: resumeLabel,
              glyph: showDetails ? glyphConfirm : null,
              onPressed: onResume,
              size: buttonSize,
            ),
            if (showDetails) ...[
              const SizedBox(width: 10),
              _DockAction(
                size: buttonSize,
                tooltip: 'Details and snapshots',
                semanticLabel: 'Details and snapshots',
                onPressed: onDetails,
                child: const Icon(Symbols.info, size: 20, color: Tokens.text),
              ),
            ],
            const SizedBox(width: 10),
            more,
          ],
        );
      case GameDockMode.stacked:
        actions = Row(
          children: [
            heart,
            const SizedBox(width: 10),
            Expanded(
              child: _DockPrimary(
                label: resumeLabel,
                glyph: null,
                onPressed: onResume,
                size: 48,
                expanded: true,
              ),
            ),
            const SizedBox(width: 10),
            more,
          ],
        );
      case GameDockMode.mini:
        actions = const SizedBox.shrink();
    }

    if (mode == GameDockMode.stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [info, const SizedBox(height: 14), actions],
      );
    }
    return Row(
      children: [
        Expanded(child: info),
        const SizedBox(width: 16),
        actions,
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.game,
    required this.mode,
    required this.meta,
    required this.status,
    required this.showMeta,
    required this.showStatus,
    this.showBadge = false,
  });

  final GameEntry game;
  final GameDockMode mode;
  final String meta;
  final String status;
  final bool showMeta;
  final bool showStatus;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final stacked = mode == GameDockMode.stacked;
    final oneLine = mode == GameDockMode.oneLine;
    final badge = Container(
      height: stacked ? 24 : 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Tokens.systemLabelBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Tokens.systemLabelBd),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          systemLabel(game.system).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tokens.systemLabel.copyWith(
            color: Tokens.systemLabelFg,
            height: null,
          ),
        ),
      ),
    );

    if (oneLine) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBadge && showMeta) ...[badge, const SizedBox(height: 8)],
          Text(
            game.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.display(
              size: 24,
              weight: FontWeight.w600,
              ls: -0.02 * 24,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            showStatus
                ? (showBadge
                      ? (game.lastPlayedMs > 0
                            ? 'Last played '
                                  '${lastPlayedLabel(game.lastPlayedMs).toLowerCase()}'
                            : 'Not played yet')
                      : '${systemLabel(game.system)} · '
                            '${game.lastPlayedMs > 0 ? lastPlayedLabel(game.lastPlayedMs).toLowerCase() : 'not played yet'}')
                : (showMeta ? meta : ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.body(size: 14, color: Tokens.muted, height: null),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMeta) ...[
          Row(
            children: [
              Flexible(child: badge),
              const SizedBox(width: 10),
              if (stacked)
                Flexible(
                  child: Text(
                    game.lastPlayedMs > 0
                        ? lastPlayedLabel(game.lastPlayedMs).toLowerCase()
                        : 'Not played yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 13,
                      color: Tokens.muted,
                      height: null,
                    ),
                  ),
                )
              else
                Flexible(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.dockMeta,
                  ),
                ),
            ],
          ),
          SizedBox(height: stacked ? 10 : 9),
        ],
        Text(
          game.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tokens.display(
            size: stacked ? 23 : 32,
            weight: FontWeight.w600,
            ls: -0.02 * (stacked ? 23 : 32),
            height: 1,
          ),
        ),
        if (showStatus && !stacked) ...[
          SizedBox(height: stacked ? 6 : 7),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.body(size: 14, color: Tokens.muted, height: null),
          ),
        ],
      ],
    );
  }
}

/// Resume / Play: the accent button, with the confirm glyph inside it.
class _DockPrimary extends StatelessWidget {
  const _DockPrimary({
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.size = 56,
    this.expanded = false,
  });

  final String label;
  final String? glyph;
  final VoidCallback onPressed;
  final double size;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return _DockAction(
      size: size,
      primary: true,
      expanded: expanded,
      tooltip: label,
      semanticLabel: label,
      onPressed: onPressed,
      padding: EdgeInsets.symmetric(horizontal: size >= 56 ? 20 : 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            _GlyphChip(glyph!, onPrimary: true),
            const SizedBox(width: 10),
          ],
          const Icon(Symbols.playArrow, size: 16, color: Colors.white, fill: 1),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tokens.body(
                size: 17,
                weight: FontWeight.w700,
                color: Colors.white,
                height: null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A focus/hover-aware dock control. Primary uses the accent fill, secondary
/// the quiet glass fill (§3.7).
class _DockAction extends StatefulWidget {
  const _DockAction({
    required this.size,
    required this.onPressed,
    required this.child,
    this.primary = false,
    this.expanded = false,
    this.padding,
    this.tooltip,
    this.semanticLabel,
  });

  final double size;
  final VoidCallback onPressed;
  final Widget child;
  final bool primary;
  final bool expanded;
  final EdgeInsets? padding;
  final String? tooltip;
  final String? semanticLabel;

  @override
  State<_DockAction> createState() => _DockActionState();
}

class _DockActionState extends State<_DockAction> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = _focus || _hover;
    final radius = BorderRadius.circular(12);
    final decoration = widget.primary
        ? BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Tokens.accentHi, Tokens.accent],
            ),
            border: const Border(top: BorderSide(color: Color(0x38FFFFFF))),
            boxShadow: active
                ? Tokens.halo
                : const [
                    BoxShadow(
                      color: Color(0xB3007BFF),
                      offset: Offset(0, 10),
                      blurRadius: 24,
                      spreadRadius: -10,
                    ),
                  ],
          )
        : BoxDecoration(
            borderRadius: radius,
            color: active ? const Color(0x1ADDE6F4) : const Color(0x0DDDE6F4),
            border: Border.all(color: const Color(0x24DDE6F4)),
            boxShadow: active ? Tokens.halo : null,
          );

    final box = AnimatedContainer(
      duration: Tokens.fastDur,
      curve: Tokens.ease,
      height: widget.size,
      constraints: widget.expanded
          ? const BoxConstraints(minWidth: 0)
          : BoxConstraints(minWidth: widget.size),
      padding:
          widget.padding ??
          EdgeInsets.symmetric(horizontal: (widget.size - 22) / 2),
      decoration: decoration,
      child: Center(
        widthFactor: widget.expanded ? null : 1,
        child: widget.child,
      ),
    );

    final body = Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        onFocusChange: (v) => setState(() => _focus = v),
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: box,
        ),
      ),
    );
    if (widget.tooltip == null) return body;
    return Tooltip(message: widget.tooltip!, child: body);
  }
}

/// A glyph chip: "Enter" on the primary, "E" on the secondary (§7.5).
class _GlyphChip extends StatelessWidget {
  const _GlyphChip(this.glyph, {required this.onPrimary});

  final String glyph;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onPrimary ? const Color(0x33060B14) : const Color(0x14DDE6F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: onPrimary ? const Color(0x33FFFFFF) : const Color(0x24DDE6F4),
        ),
      ),
      child: Text(
        glyph,
        maxLines: 1,
        style: Tokens.glyphChip.copyWith(
          color: onPrimary ? Colors.white : Tokens.text,
          fontSize: 12,
        ),
      ),
    );
  }
}
