import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';

/// One of the five ways the library can show a collection.
///
/// The value is the one stored in `libraryViewKey` and shared with Settings,
/// so the first-run choice is the same preference the rest of the app reads.
class LibraryLook {
  const LibraryLook(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

/// The five looks, in the order the design lists them.
const libraryLooks = <LibraryLook>[
  LibraryLook('3d', '3D shelf', 'Covers turn in space, one at a time.'),
  LibraryLook('shelf', 'Shelf', 'Rows: continue, handhelds, consoles.'),
  LibraryLook('wall', 'Wall', 'A curved wall you look along.'),
  LibraryLook('grid', 'Grid', 'Every cover at a glance.'),
  LibraryLook('list', 'List', 'Titles and details in columns.'),
];

/// The look a collection starts with.
const defaultLibraryLook = '3d';

/// Five live miniature previews of the library looks.
///
/// On a phone the chosen look gets the full-width 170 px card and the other
/// four pair up beneath it in 128 px cards, as in the device frame. On wider
/// screens all five sit in one centred row of 200 px cards.
class LookPicker extends StatelessWidget {
  const LookPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.phone = false,
  });

  /// The stored look value (`3d`, `shelf`, `wall`, `grid`, `list`).
  final String selected;

  final ValueChanged<String> onSelected;

  /// Phone portrait: one featured card and a two-by-two grid.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final chosen = libraryLooks.firstWhere(
      (look) => look.value == selected,
      orElse: () => libraryLooks.first,
    );

    if (!phone) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final look in libraryLooks)
            SizedBox(
              width: 200,
              child: _LookCard(
                key: Key('look-card-${look.value}'),
                look: look,
                selected: look.value == chosen.value,
                onTap: () => onSelected(look.value),
              ),
            ),
        ],
      );
    }

    final others = [
      for (final look in libraryLooks)
        if (look.value != chosen.value) look,
    ];
    final cards = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _featuredHeight,
          child: _LookCard(
            key: Key('look-card-${chosen.value}'),
            look: chosen,
            selected: true,
            featured: true,
            phone: true,
            autofocus: true,
            onTap: () => onSelected(chosen.value),
          ),
        ),
        const SizedBox(height: 11),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 11),
          SizedBox(
            height: _compactHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 2; column++) ...[
                  if (column > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _LookCard(
                      key: Key('look-card-${others[row * 2 + column].value}'),
                      look: others[row * 2 + column],
                      selected: false,
                      phone: true,
                      onTap: () => onSelected(others[row * 2 + column].value),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    // The selected card's blue drop shadow, painted as gradients so it also
    // reads where the renderer draws no blurred shadows. A broad edge wash
    // plus a stronger core under the card matches the design's halo.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 168,
          left: -16,
          right: -16,
          height: 64,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Tokens.accent.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 168,
          left: 0,
          right: 0,
          height: 64,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Tokens.accent.withValues(alpha: 0.24),
                    Tokens.accent.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.4, 1],
                ),
              ),
            ),
          ),
        ),
        cards,
      ],
    );
  }
}

/// Phone measurements from the 390 × 844 first-run frame.
const _featuredHeight = 170.0;
const _compactHeight = 128.0;

/// A miniature of one library look, painted from the prototype's cells.
class LookPreview extends StatelessWidget {
  const LookPreview({
    super.key,
    required this.look,
    this.active = false,
    this.scale = 1,
  });

  final String look;

  /// The chosen look lights its cells and the highlight cell in accent blue.
  final bool active;

  /// Size multiplier applied to the 168 × 100 design canvas.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        // The design's 60% preview wash, resolved over the card behind it.
        color: active ? const Color(0xFF060E1B) : const Color(0xFF080D15),
        child: CustomPaint(
          painter: _LookPreviewPainter(
            look: look,
            active: active,
            scale: scale,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _LookCard extends StatefulWidget {
  const _LookCard({
    super.key,
    required this.look,
    required this.selected,
    required this.onTap,
    this.featured = false,
    this.phone = false,
    this.autofocus = false,
  });

  final LibraryLook look;
  final bool selected;
  final VoidCallback onTap;

  /// The chosen look's full-width card on a phone.
  final bool featured;

  /// Phone cards hide the description and use the tighter preview.
  final bool phone;

  /// The chosen card starts with the shared focus so the phone frame reads.
  final bool autofocus;

  @override
  State<_LookCard> createState() => _LookCardState();
}

class _LookCardState extends State<_LookCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final active = _hover || _focus;
    final selected = widget.selected;
    final featured = widget.featured;
    final compact = widget.phone && !featured;

    final previewHeight = featured
        ? 120.0
        : compact
        ? 84.0
        : 100.0;
    final previewScale = featured
        ? 1.11
        : compact
        ? 0.84
        : 1.0;
    final radius = featured
        ? 18.0
        : compact
        ? 16.0
        : 18.0;
    final padding = featured
        ? const EdgeInsets.fromLTRB(10, 10, 10, 0)
        : compact
        ? const EdgeInsets.fromLTRB(10, 8, 10, 0)
        : const EdgeInsets.all(16);
    final labelStyle = Tokens.body(
      size: featured || compact ? 15 : 17,
      weight: FontWeight.w700,
      color: Colors.white,
      height: 1,
    );

    // The halo is painted behind the card, so a focused/selected card needs
    // an opaque fill or the solid accent ring washes through the whole card.
    final decoration = BoxDecoration(
      color: selected
          ? const Color(0xFF051931) // accent .12 over ink
          : active
          ? const Color(0xFF0F141D) // white .04 over ink
          : const Color(0x0ADDE6F4),
      borderRadius: BorderRadius.circular(radius),
      border: featured
          ? null
          : Border.all(
              color: selected
                  ? Tokens.accent.withValues(alpha: 0.6)
                  : const Color(0x1FDDE6F4),
              width: 1,
            ),
      boxShadow: featured
          ? Tokens.halo
          : active
          ? Tokens.halo
          : null,
    );

    final labelRow = SizedBox(
      height: featured
          ? 40
          : compact
          ? 34
          : 20,
      child: Padding(
        padding: EdgeInsets.only(
          left: featured ? 4 : (compact ? 3 : 0),
          right: featured ? 4 : 0,
        ),
        child: Row(
          children: [
            Expanded(
              child: Transform.translate(
                offset: Offset(0, featured ? -2 : (compact ? -1 : 0)),
                child: Text(
                  widget.look.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
            ),
            if (selected)
              Icon(
                Symbols.checkCircle,
                key: Key('look-check-${widget.look.value}'),
                size: 20,
                fill: 1,
                color: Tokens.iconBlue,
              ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '${widget.look.label} look',
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        onShowFocusHighlight: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: AnimatedScale(
          scale: active && !reduce ? 1.02 : 1,
          duration: reduce ? Duration.zero : Tokens.fastDur,
          curve: Tokens.ease,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : Tokens.fastDur,
              curve: Tokens.ease,
              padding: padding,
              decoration: decoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: previewHeight,
                    child: LookPreview(
                      look: widget.look.value,
                      active: selected,
                      scale: previewScale,
                    ),
                  ),
                  if (!featured && !compact) const SizedBox(height: 14),
                  if (featured || compact)
                    labelRow
                  else ...[
                    labelRow,
                    const SizedBox(height: 6),
                    Text(
                      widget.look.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: 13.5,
                        color: Tokens.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LookPreviewPainter extends CustomPainter {
  const _LookPreviewPainter({
    required this.look,
    required this.active,
    required this.scale,
  });

  final String look;
  final bool active;
  final double scale;

  static const _dimCell = Color(0x21DDE6F4); // rgba(221,230,244,.13)
  static const _litCell = Color(0x4DDDE6F4); // rgba(221,230,244,.30)
  static const _accentCell = Color(0xCC007BFF); // rgba(0,123,255,.80)
  static const _lineColor = Color(0xD93B8BFF); // rgba(59,139,255,.85)

  Color get _a => active ? _accentCell : _litCell;

  Color get _b => active ? _litCell : _dimCell;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = 168.0 * scale;
    final height = 100.0 * scale;
    canvas.save();
    canvas.translate((size.width - width) / 2, (size.height - height) / 2);
    canvas.scale(scale);
    switch (look) {
      case 'shelf':
        _shelf(canvas);
      case 'wall':
        _wall(canvas);
      case 'grid':
        _grid(canvas);
      case 'list':
        _list(canvas);
      default:
        _shelf3d(canvas);
    }
    canvas.restore();
  }

  void _shelf3d(Canvas canvas) {
    _cell(canvas, 8, 34, 22, 32, _b, angle: 55);
    _cell(canvas, 30, 30, 26, 38, _b, angle: 45);
    _cell(canvas, 66, 20, 36, 52, _a);
    _cell(canvas, 112, 30, 26, 38, _b, angle: -45);
    _cell(canvas, 138, 34, 22, 32, _b, angle: -55);
    _line(canvas, 40, 86, 88);
  }

  void _shelf(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      _cell(canvas, 10 + i * 52.0, 10, 46, 30, i == 0 ? _a : _b);
    }
    _line(canvas, 0, 45, 168);
    for (var i = 0; i < 6; i++) {
      _cell(canvas, 10 + i * 26.0, 54, 20, 30, _b);
    }
    _line(canvas, 0, 88, 168);
  }

  void _wall(Canvas canvas) {
    for (var row = 0; row < 3; row++) {
      for (var i = 0; i < 6; i++) {
        final distance = i - 2.5;
        _cell(
          canvas,
          14 + i * 24.0,
          10 + row * 28.0,
          20,
          24,
          row == 1 && i == 2 ? _a : _b,
          narrow: 1 - distance.abs() * 0.13,
        );
      }
    }
  }

  void _grid(Canvas canvas) {
    for (var row = 0; row < 3; row++) {
      for (var i = 0; i < 7; i++) {
        _cell(
          canvas,
          11 + i * 21.0,
          10 + row * 28.0,
          17,
          23,
          row == 0 && i == 0 ? _a : _b,
        );
      }
    }
  }

  void _list(Canvas canvas) {
    for (var row = 0; row < 5; row++) {
      _cell(canvas, 14, 10 + row * 17.0, 12, 12, row == 0 ? _a : _b);
      _rect(
        canvas,
        32,
        13 + row * 17.0,
        row == 0 ? 96 : (70 + (row * 37) % 30).toDouble(),
        6,
        row == 0 ? _a : _b,
      );
      _rect(canvas, 140, 13 + row * 17.0, 14, 6, _b);
    }
  }

  void _cell(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    Color color, {
    double angle = 0,
    double narrow = 1,
  }) {
    final projected = width * narrow * math.cos(angle.abs() * math.pi / 180);
    final left = x + (width - projected) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y, projected, height),
        const Radius.circular(3),
      ),
      Paint()..color = color,
    );
  }

  void _rect(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    Color color,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(3),
      ),
      Paint()..color = color,
    );
  }

  void _line(Canvas canvas, double x, double y, double width) {
    _rect(canvas, x, y, width, 4, _lineColor.withValues(alpha: 0.16));
    _rect(canvas, x, y + 1.25, width, 1.5, _lineColor);
  }

  @override
  bool shouldRepaint(_LookPreviewPainter old) =>
      old.look != look || old.active != active || old.scale != scale;
}
