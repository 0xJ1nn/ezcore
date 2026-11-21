import 'package:flutter/material.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'library_header.dart' show LibraryLook;
import 'library_looks/library_cover.dart' show LibraryCover;
import 'library_looks/look_picker_sheet.dart' show lookSubtitle;

/// The five library looks as cards, shown on first run.
///
/// The sheet in Settings presents the same five looks as rows; first run
/// needs the design's card presentation instead, so this widget keeps that
/// layout without a second set of look values or cover artwork. Each preview
/// is the library's own generated [LibraryCover], at thumbnail size.
class OnboardingLookPicker extends StatelessWidget {
  const OnboardingLookPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.phone = false,
  });

  /// The look saved under the library's view setting.
  final LibraryLook selected;

  /// Called with the look the person taps.
  final ValueChanged<LibraryLook> onSelected;

  /// Portrait phones show the chosen look full width and pair the other four
  /// beneath it; wider screens show all five in one row.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    if (!phone) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final look in LibraryLook.values)
            SizedBox(
              width: 200,
              child: _LookCard(
                key: Key('look-card-${look.value}'),
                look: look,
                selected: look == selected,
                onTap: () => onSelected(look),
              ),
            ),
        ],
      );
    }

    final others = [
      for (final look in LibraryLook.values)
        if (look != selected) look,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _featuredHeight,
          child: _LookCard(
            key: Key('look-card-${selected.value}'),
            look: selected,
            selected: true,
            featured: true,
            phone: true,
            autofocus: true,
            onTap: () => onSelected(selected),
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
                      onTap: () => onSelected(others[row * 2 + column]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

const _featuredHeight = 170.0;
const _compactHeight = 128.0;

/// A generated cover under the look's name. The covers are invented previews,
/// never box art or game screenshots.
({String title, String system}) _previewFor(LibraryLook look) => switch (look) {
  LibraryLook.flow => (title: 'Lanterns of Vell', system: 'nds'),
  LibraryLook.shelf => (title: 'Meadow Isles', system: 'snes'),
  LibraryLook.wall => (title: 'Deep Orbit', system: 'gc'),
  LibraryLook.grid => (title: 'Bluestreak', system: 'genesis'),
  LibraryLook.list => (title: 'Glasswing', system: 'psx'),
};

class _LookPreview extends StatelessWidget {
  const _LookPreview({required this.look, required this.compact});

  final LibraryLook look;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final preview = _previewFor(look);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xFF080D15),
        child: Center(
          // Preview covers are sample art, not real entries with a file on
          // disk — leave contentPresent at its default of true.
          child: LibraryCover(
            gameId: 'onboarding-${look.value}',
            title: preview.title,
            systemId: preview.system,
            width: compact ? 56 : 96,
            height: compact ? 72 : 118,
            radius: 7,
          ),
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
  final bool featured;
  final bool phone;
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
    final featured = widget.featured;
    final compact = widget.phone && !featured;
    final showDetails = !widget.phone;

    final previewHeight = featured ? 120.0 : compact ? 84.0 : 100.0;
    final padding = featured
        ? const EdgeInsets.fromLTRB(10, 10, 10, 0)
        : compact
        ? const EdgeInsets.fromLTRB(10, 8, 10, 0)
        : const EdgeInsets.all(16);
    final radius = featured || !widget.phone ? 18.0 : 16.0;
    final labelStyle = Tokens.body(
      size: widget.phone ? 15 : 17,
      weight: FontWeight.w700,
      color: Colors.white,
      height: 1,
    );

    final decoration = BoxDecoration(
      color: widget.selected
          ? const Color(0xFF051931)
          : active
          ? const Color(0xFF0F141D)
          : const Color(0x0ADDE6F4),
      borderRadius: BorderRadius.circular(radius),
      border: featured
          ? null
          : Border.all(
              color: widget.selected
                  ? Tokens.accent.withValues(alpha: 0.6)
                  : const Color(0x1FDDE6F4),
            ),
      boxShadow: featured || active ? Tokens.halo : null,
    );

    return Semantics(
      button: true,
      selected: widget.selected,
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: active && !reduce ? 1.02 : 1,
            duration: reduce ? Duration.zero : Tokens.fastDur,
            curve: Tokens.ease,
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
                    child: _LookPreview(
                      look: widget.look,
                      compact: compact,
                    ),
                  ),
                  if (showDetails) const SizedBox(height: 14),
                  SizedBox(
                    height: showDetails ? 20 : 34,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.look.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                        if (widget.selected)
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
                  if (showDetails) ...[
                    const SizedBox(height: 6),
                    Text(
                      lookSubtitle(widget.look),
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
