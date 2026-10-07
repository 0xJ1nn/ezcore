import 'package:flutter/material.dart';

import '../services/gamepad.dart';

/// Whether a controller drives the menus. The player turns this off while a
/// game has the controller and back on while its pause menu or an editor is
/// open, so the same d-pad never both moves the menu focus and the game.
final padNavigationEnabled = ValueNotifier<bool>(true);

/// Lets a controller drive every menu: d-pad moves focus, A activates what
/// is focused, B goes back. Works with any widget Flutter can focus and
/// activate (buttons, list items, game tiles), so screens need nothing extra.
class PadNavigator extends StatefulWidget {
  const PadNavigator({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.subscribe,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Subscribes to controller presses; defaults to the shared pad service.
  /// Returns the cancel function.
  final void Function() Function(void Function(GamepadEvent))? subscribe;

  @override
  State<PadNavigator> createState() => _PadNavigatorState();
}

class _PadNavigatorState extends State<PadNavigator> {
  void Function()? _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = (widget.subscribe ?? GamepadService.shared.onButton)(_onPad);
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  void _onPad(GamepadEvent e) {
    if (!e.pressed || !padNavigationEnabled.value) return;
    final focus = FocusManager.instance.primaryFocus;
    final dir = switch (e.code) {
      'up' => TraversalDirection.up,
      'down' => TraversalDirection.down,
      'left' => TraversalDirection.left,
      'right' => TraversalDirection.right,
      _ => null,
    };
    if (dir != null) {
      if (focus == null) {
        FocusManager.instance.rootScope.nextFocus();
      } else if (focus is FocusScopeNode) {
        // A screen is focused but no control in it yet: take the first one.
        focus.nextFocus();
      } else {
        // A widget that browses on its own (the 3D shelf) overrides the
        // directional intent the arrow keys send; give it the d-pad too.
        // Flutter's default action is skipped on purpose: it ignores text
        // fields, which would trap the d-pad in the search box.
        final ctx = focus.context;
        final intent = DirectionalFocusIntent(dir);
        final action = ctx == null
            ? null
            : Actions.maybeFind<DirectionalFocusIntent>(ctx, intent: intent);
        if (action != null && action is! DirectionalFocusAction) {
          Actions.invoke(ctx!, intent);
        } else {
          focus.focusInDirection(dir);
        }
      }
      return;
    }
    switch (e.code) {
      case 'a':
      case 'start':
        final ctx = focus?.context;
        if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      case 'b':
        widget.navigatorKey.currentState?.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
