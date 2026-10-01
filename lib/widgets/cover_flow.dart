import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A 3D shelf: the focused item faces you, its neighbours turn away in
/// perspective on either side.
///
/// An invisible [PageView] supplies the drag, fling and snap physics; the
/// covers are painted in a [Stack] ordered by distance, so the focused one is
/// always on top (a PageView paints left to right, which would bury it).
///
/// Input: drag or swipe, the mouse wheel, ← → on a keyboard, the d-pad on a
/// controller (through [DirectionalFocusIntent]), and Enter / A on the focused
/// item. Tapping a neighbour brings it to the front; tapping the front item
/// activates it.
class CoverFlow extends StatefulWidget {
  const CoverFlow({
    super.key,
    required this.count,
    required this.index,
    required this.onIndexChanged,
    required this.onActivate,
    required this.itemBuilder,
    required this.itemSize,
    this.focusNode,
    this.semanticLabel,
    this.showArrows = false,
  });

  final int count;

  /// The focused item. The parent owns it so a filter change can move it.
  final int index;
  final ValueChanged<int> onIndexChanged;
  final ValueChanged<int> onActivate;

  /// Builds item [i]; [front] is true for the focused item.
  final Widget Function(BuildContext context, int i, bool front) itemBuilder;
  final Size itemSize;
  final FocusNode? focusNode;
  final String? semanticLabel;

  /// Round ← → buttons at the edges, for mouse users.
  final bool showArrows;

  @override
  State<CoverFlow> createState() => _CoverFlowState();
}

class _CoverFlowState extends State<CoverFlow> {
  PageController? _controller;
  double _fraction = 0;
  FocusNode? _ownFocus;
  bool _focused = false;

  FocusNode get _focus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'cover flow'));

  /// Horizontal distance between the front item and its first neighbour,
  /// and between neighbours further out.
  double get _near => widget.itemSize.width * 0.74;
  double get _far => widget.itemSize.width * 0.36;

  PageController _controllerFor(double width) {
    final fraction = (_near / width).clamp(0.05, 1.0);
    if (_controller == null || (fraction - _fraction).abs() > 0.001) {
      final page = _controller?.hasClients == true
          ? (_controller!.page ?? widget.index.toDouble()).round()
          : widget.index;
      _controller?.dispose();
      _controller = PageController(
        viewportFraction: fraction,
        initialPage: page,
      );
      _fraction = fraction;
    }
    return _controller!;
  }

  @override
  void didUpdateWidget(CoverFlow old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final current = (c.page ?? widget.index.toDouble()).round();
    if (widget.index != current && widget.index < widget.count) {
      c.jumpToPage(widget.index);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (widget.count == 0) return;
    final target = i.clamp(0, widget.count - 1);
    final c = _controller;
    if (c == null || !c.hasClients) {
      widget.onIndexChanged(target);
      return;
    }
    c.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Tokens.ease,
    );
  }

  int get _current {
    final c = _controller;
    if (c == null || !c.hasClients) return widget.index;
    return (c.page ?? widget.index.toDouble()).round();
  }

  Object? _direction(DirectionalFocusIntent intent) {
    switch (intent.direction) {
      case TraversalDirection.left:
        _go(_current - 1);
      case TraversalDirection.right:
        _go(_current + 1);
      case TraversalDirection.up:
      case TraversalDirection.down:
        // Up and down leave the shelf, to the filters or the action bar.
        FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
    }
    return null;
  }

  void _onTap(TapUpDetails d, double width) {
    final dx = d.localPosition.dx - width / 2;
    final step = dx.abs() <= widget.itemSize.width / 2
        ? 0
        : dx.sign * (1 + ((dx.abs() - _near) / _far).clamp(0, 3).floor());
    final target = (_current + step).clamp(0, widget.count - 1).toInt();
    _focus.requestFocus();
    if (target == _current) {
      widget.onActivate(target);
    } else {
      _go(target);
    }
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final d = e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()
        ? e.scrollDelta.dx
        : e.scrollDelta.dy;
    if (d.abs() < 4) return;
    GestureBinding.instance.pointerSignalResolver.register(
      e,
      (_) => _go(_current + d.sign.toInt()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: _direction,
        ),
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (widget.count > 0) widget.onActivate(_current);
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focus,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Semantics(
          label: widget.semanticLabel,
          hint:
              'Swipe or use the arrow keys to browse; open the front one for '
              'its page',
          child: LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth;
              final controller = _controllerFor(width);
              return Listener(
                onPointerSignal: _onWheel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d, width),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) =>
                            _shelf(context, controller, width, c.maxHeight),
                      ),
                      // Physics only: transparent pages under the pointer.
                      ScrollConfiguration(
                        behavior: const _DragEverywhere(),
                        child: PageView.builder(
                          controller: controller,
                          itemCount: widget.count,
                          onPageChanged: widget.onIndexChanged,
                          itemBuilder: (_, _) => const SizedBox.expand(),
                        ),
                      ),
                      if (widget.showArrows)
                        AnimatedBuilder(
                          animation: controller,
                          builder: (context, _) => Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              CoverFlowArrow(
                                left: true,
                                onPressed: _current > 0
                                    ? () => _go(_current - 1)
                                    : null,
                              ),
                              CoverFlowArrow(
                                left: false,
                                onPressed: _current < widget.count - 1
                                    ? () => _go(_current + 1)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _shelf(
    BuildContext context,
    PageController controller,
    double width,
    double height,
  ) {
    final page = controller.hasClients && controller.position.haveDimensions
        ? controller.page ?? widget.index.toDouble()
        : widget.index.toDouble();
    final visible = <int>[
      for (var i = (page - 5).floor(); i <= (page + 5).ceil(); i++)
        if (i >= 0 && i < widget.count) i,
    ]..sort((a, b) => (b - page).abs().compareTo((a - page).abs()));
    final front = page.round();
    final w = widget.itemSize.width;
    final h = widget.itemSize.height;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final i in visible)
          _placed(context, i, i - page, i == front, width, height, w, h),
      ],
    );
  }

  Widget _placed(
    BuildContext context,
    int i,
    double delta,
    bool front,
    double width,
    double height,
    double w,
    double h,
  ) {
    final d = delta.abs();
    final near = math.min(d, 1.0);
    final x = delta.sign * (near * _near + math.max(d - 1, 0) * _far);
    final scale = 1 - 0.13 * math.min(d, 2.0);
    final angle = -delta.sign * near * 48 * math.pi / 180;
    final dim = (0.62 * math.min(d, 1.6) / 1.6).clamp(0.0, 0.62);
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0008)
      ..rotateY(angle)
      ..scaleByDouble(scale, scale, 1, 1);
    return Positioned(
      left: width / 2 + x - w / 2,
      top: (height - h) / 2,
      width: w,
      height: h,
      child: Transform(
        alignment: Alignment.center,
        transform: matrix,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.radiusCover + 2),
                border: Border.all(
                  color: front && _focused
                      ? Tokens.accent
                      : const Color(0x00000000),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: front
                        ? const Color(0x66007BFF)
                        : const Color(0x99000000),
                    blurRadius: front ? 38 : 18,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.5),
                child: widget.itemBuilder(context, i, front),
              ),
            ),
            if (dim > 0)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(4, 8, 14, dim),
                    borderRadius: BorderRadius.circular(Tokens.radiusCover + 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mouse and trackpad drags move the shelf too (desktop scrollables ignore
/// mouse drags by default).
class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// A round arrow button at the shelf's edge.
class CoverFlowArrow extends StatelessWidget {
  const CoverFlowArrow({
    super.key,
    required this.left,
    required this.onPressed,
  });

  final bool left;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB30B1421),
      shape: const CircleBorder(side: BorderSide(color: Tokens.lineStrong)),
      child: InkWell(
        customBorder: const CircleBorder(),
        canRequestFocus: false,
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            left ? Icons.chevron_left : Icons.chevron_right,
            color: onPressed == null ? Tokens.separator : Tokens.text,
          ),
        ),
      ),
    );
  }
}
