import 'dart:math' as math;
import 'dart:ui' as ui;

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
    this.reflection = false,
    this.autofocus = false,
    this.angle = 58,
    this.frontScale = 1.04,
    this.spread = 0.62,
    this.reflectionRatio = 0.11,
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

  /// Mirror each item on a glossy floor below it.
  final bool reflection;

  /// Take keyboard focus when nothing below the screen's own focus has it,
  /// so ← → work straight away.
  final bool autofocus;

  /// How far each neighbour turns away, in degrees (58 in the design).
  final double angle;

  /// The focused cover comes forward 60 px by growing 4% (§8.1).
  final double frontScale;

  /// Distance to the first neighbour, as a share of the cover's width.
  final double spread;

  /// Reflection height, as a share of the cover's height.
  final double reflectionRatio;

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

  /// Horizontal centre distance from the front item to its first neighbour,
  /// and between the neighbours further out. The design stacks covers almost
  /// edge to edge, so the first step is wider than the rest.
  // Prototype: first neighbour 196 px, each further one 104 px (at a 270 px
  // cover). Scaled to the cover's actual width.
  double get _near => widget.itemSize.width * (196 / 270);
  double get _far => widget.itemSize.width * (104 / 270);

  /// Reflection height, as a share of the item's.
  double get _mirror => widget.reflectionRatio;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = FocusManager.instance.primaryFocus;
        // Only when focus sits above the shelf (the screen itself), never
        // when someone is typing in a field or using another control.
        if (current == null || _focus.ancestors.contains(current)) {
          _focus.requestFocus();
        }
      });
    }
  }

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
    // The parent moved the front item (a filter, a new sort). Jumping notifies
    // the shelf's listeners, which must not happen mid-build: do it after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _controller;
      if (!mounted || c == null || !c.hasClients) return;
      final current = (c.page ?? widget.index.toDouble()).round();
      if (widget.index != current && widget.index < widget.count) {
        c.jumpToPage(widget.index);
      }
    });
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
                      // Physics only: transparent pages that take the drags.
                      // First, so a new controller attaches before anything
                      // listening to it has built (attaching notifies).
                      ScrollConfiguration(
                        behavior: const _DragEverywhere(),
                        child: PageView.builder(
                          controller: controller,
                          itemCount: widget.count,
                          onPageChanged: widget.onIndexChanged,
                          itemBuilder: (_, _) => const SizedBox.expand(),
                        ),
                      ),
                      // The covers, painted over the physics layer; pointers
                      // pass through to it (taps are handled above).
                      IgnorePointer(
                        child: AnimatedBuilder(
                          animation: controller,
                          builder: (context, _) =>
                              _shelf(context, controller, width, c.maxHeight),
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

  /// Where the front item's top edge sits: centred, a little high when a
  /// reflection needs the floor below it.
  double _top(double height, double h) {
    final total = widget.reflection ? h * (1 + _mirror) : h;
    return math.max(0, (height - total) / 2);
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
      for (var i = (page - 6).floor(); i <= (page + 6).ceil(); i++)
        if (i >= 0 && i < widget.count) i,
    ]..sort((a, b) => (b - page).abs().compareTo((a - page).abs()));
    final front = page.round();
    final w = widget.itemSize.width;
    final h = widget.itemSize.height;
    final top = _top(height, h);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Floor glow under the centre cover (prototype: 520×80, blur 8).
        Positioned(
          left: width / 2 - 260,
          top: top + h - 24,
          width: 520,
          height: 80,
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(260, 40)),
                  gradient: RadialGradient(
                    colors: [Color(0x61007BFF), Color(0x00007BFF)],
                    stops: [0, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final i in visible)
          _placed(context, i, i - page, i == front, width, top, w, h),
      ],
    );
  }

  Widget _placed(
    BuildContext context,
    int i,
    double delta,
    bool front,
    double width,
    double top,
    double w,
    double h,
  ) {
    final ad = delta.abs();
    final near = math.min(ad, 1.0);
    final x = delta.sign *
        (ad < 1
            ? _near * ad
            : _near + (ad - 1) * _far);
    final angle = -delta.sign * near * widget.angle * math.pi / 180;
    final scale = front ? widget.frontScale : 1.0;
    // Prototype translateZ: centre 60 (focused) / 20, neighbours -150 -(a-1)*30.
    final frontZ = _focused ? 60.0 : 20.0;
    final z = ad < 1
        ? frontZ * (1 - ad) - 150.0 * ad
        : -150.0 - (ad - 1.0) * 30.0;
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 1 / 1500)
      ..rotateY(angle)
      ..translateByDouble(0.0, 0.0, z, 1.0)
      ..scaleByDouble(scale, scale, 1, 1);
    final radius = BorderRadius.circular(7);
    final cover = Stack(
      fit: StackFit.expand,
      children: [
        widget.itemBuilder(context, i, front),
        // Prototype shade: darkens the inner edge of each neighbour.
        if (!front)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    delta > 0
                        ? const Color(0x8C060B14)
                        : Colors.transparent,
                    delta < 0
                        ? const Color(0x8C060B14)
                        : Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        // Focus border on top of the cover (prototype: 1px accent for the
        // front item, HALO handled by the shelf's focus).
        if (front)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _focused ? Tokens.accentHi : Tokens.accent,
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x8C007BFF),
                    blurRadius: 34,
                    spreadRadius: -4,
                  ),
                ],
              ),
            ),
          )
        else
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 22,
                    spreadRadius: -2,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final mirror = h * _mirror;
    return Positioned(
      left: width / 2 + x - w / 2,
      // Neighbours sit a touch further back, on the same floor plane.
      top: top + (front ? 0 : 10),
      width: w,
      height: widget.reflection ? h + 10 + mirror : h,
      child: Transform(
        // Turn about the cover's own centre, not the cover plus reflection.
        alignment: Alignment(
          0,
          widget.reflection ? -1 + h / (h + 10 + mirror) : 0,
        ),
        transform: matrix,
        child: widget.reflection
            ? Column(
                children: [
                  SizedBox(height: h, child: cover),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: mirror,
                    child: IgnorePointer(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (r) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x26FFFFFF),
                          ],
                          stops: [0.0, 0.74, 1.0],
                        ).createShader(r),
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: h,
                            maxHeight: h,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.diagonal3Values(1, -1, 1),
                              child: ClipRRect(
                                borderRadius: radius,
                                child: widget.itemBuilder(context, i, false),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : cover,
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
