import 'package:flutter/material.dart';

/// An [IndexedStack] that fades the new page in when [index] changes, so
/// moving between destinations feels like one place rather than a cut.
/// Every page keeps its state (scroll position, filters). Honours the
/// system's reduce-motion setting.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 200),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration, value: 1);

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      reduce ? _c.value = 1 : _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
    child: IndexedStack(index: widget.index, children: widget.children),
  );
}
