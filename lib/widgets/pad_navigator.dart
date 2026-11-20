import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/gamepad.dart';
import '../state/input_mode.dart';

/// Whether a controller drives the menus. The player turns this off while a
/// game has the controller and back on while its pause menu or an editor is
/// open, so the same d-pad never both moves the menu focus and the game.
final padNavigationEnabled = ValueNotifier<bool>(true);

/// A nudge at the end of a row. [id] is the registered id of the focused
/// widget, so only that widget reacts; [direction] says which wall it hit.
class EdgeSignal {
  const EdgeSignal(this.id, this.direction, this.sequence);

  final String id;
  final TraversalDirection direction;
  final int sequence;
}

/// Repeats a directional move the way the handoff asks (§4.1): one step
/// immediately, nothing for 380 ms while the key is still held, then a step
/// every 110 ms. Kept separate from [FocusOwner] so the timing is testable on
/// its own with a fake clock.
class KeyRepeater {
  KeyRepeater(this.onMove);

  /// When a held direction starts repeating, and how often it repeats after.
  static const initialDelay = Duration(milliseconds: 380);
  static const interval = Duration(milliseconds: 110);

  final VoidCallback onMove;
  Timer? _initial;
  Timer? _periodic;

  bool get running => _initial != null || _periodic != null;

  /// Starts (or restarts) the repeat. The caller is responsible for the first,
  /// immediate move; the timer only produces the held repeats.
  void start() {
    stop();
    _initial = Timer(initialDelay, () {
      _initial = null;
      onMove();
      _periodic = Timer.periodic(interval, (_) => onMove());
    });
  }

  void stop() {
    _initial?.cancel();
    _periodic?.cancel();
    _initial = null;
    _periodic = null;
  }
}

/// The one owner of focus in the app.
///
/// Mouse hover, arrow keys and the d-pad all write to this owner, so exactly
/// one element shows the halo at a time (handoff §4.1). It also remembers the
/// focus of every rail destination, hands focus to the rail at the left edge
/// and back again at the right, traps focus inside popups, and returns it to
/// the element that opened them when B closes them.
class FocusOwner extends ChangeNotifier {
  FocusOwner._();

  /// The app-wide instance. [PadNavigator], [FocusGlow] and the shell all talk
  /// to this, which is what makes it a single owner rather than two.
  static final FocusOwner shared = FocusOwner._();

  /// How far a focused widget nudges into the wall at a row's end (§5), and
  /// how long that takes. Both are in the "edge bump" line of the motion table.
  static const double edgeNudge = 7;
  static const Duration edgeDuration = Duration(milliseconds: 140);

  /// Analogue sticks use a wider dead zone for menu navigation than the
  /// 0.12 used for game input (§4.1).
  static const double analogDeadZone = 0.55;

  /// The last direction a key or a stick asked for; the shell uses this to
  /// nudge the selected cover rather than the first one when coming back up
  /// from the dock.
  TraversalDirection? lastDirection;

  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  final Map<FocusNode, String> _ids = <FocusNode, String>{};
  final Map<String, FocusNode> _focusByScreen = <String, FocusNode>{};

  String _screen = 'library';
  String get screen => _screen;

  FocusNode? _rail;
  FocusNode? _returnFromRail;
  FocusNode? _selectedCover;

  FocusNode? _opener;
  FocusNode? _modalFocus;
  FocusScopeNode? _modalScope;
  int _modalDepth = 0;
  bool get modalOpen => _modalDepth > 0;

  int _edgeSequence = 0;
  final ValueNotifier<EdgeSignal?> edge = ValueNotifier<EdgeSignal?>(null);

  final KeyRepeater _repeater = KeyRepeater(() {
    final dir = FocusOwner.shared.lastDirection;
    if (dir != null) FocusOwner.shared.move(dir);
  });
  final Set<LogicalKeyboardKey> _heldKeys = <LogicalKeyboardKey>{};

  /// Registers a focusable under a stable id so it can be remembered and
  /// targeted by an edge bump. Ids are per widget, not per screen instance,
  /// because a cover keeps its id while the screen around it changes.
  void register(String id, FocusNode node) {
    _nodes[id] = node;
    _ids[node] = id;
  }

  void unregister(String id, FocusNode node) {
    if (identical(_nodes[id], node)) _nodes.remove(id);
    _ids.remove(node);
    if (identical(_focusByScreen[_screen], node)) {
      _focusByScreen.remove(_screen);
    }
    if (identical(_returnFromRail, node)) _returnFromRail = null;
    if (identical(_selectedCover, node)) _selectedCover = null;
  }

  /// The id [node] was registered under, so a widget can tell whether an
  /// [edge] signal belongs to it without keeping a second copy of the id.
  String? idOf(FocusNode node) => _ids[node];

  /// Sends an edge bump to a widget that consumes left/right itself (the 3D
  /// shelf). Its DirectionalFocusIntent always reports a step as handled, so
  /// [move] never sees the failed traversal that would otherwise call [_bump].
  void edgeBump(TraversalDirection dir, FocusNode node) => _bump(dir, node);

  /// The rail is a focus group beside the screen: left from the screen's
  /// first column lands here, right here returns to the screen.
  void attachRail(FocusNode node) {
    _rail = node;
    register('__rail', node);
  }

  void detachRail(FocusNode node) {
    if (identical(_rail, node)) _rail = null;
    unregister('__rail', node);
  }

  /// The cover the shelf currently shows. Coming back up from the dock must
  /// land here, not on the first cover of the collection.
  void setSelectedCover(FocusNode node) => _selectedCover = node;

  FocusNode? get remembered => _focusByScreen[_screen];
  FocusNode? get rail => _rail;
  FocusNode? get selectedCover => _selectedCover;
  FocusNode? get opener => _opener;

  void _focus(FocusNode node) {
    if (node.context?.mounted ?? false) node.requestFocus();
  }

  /// Enters a destination and restores the focus it had last time. Coming
  /// back from the rail takes the same path, because the rail calls [setScreen].
  void setScreen(String id, {FocusNode? initial}) {
    _screen = id;
    _repeater.stop();
    final target = _focusByScreen[id] ?? initial;
    if (target != null) _focus(target);
    notifyListeners();
  }

  /// Records that [node] is now the single focus of the current screen.
  /// Popup focus is deliberately not remembered: it belongs to the opener.
  void remember(FocusNode node) {
    if (modalOpen) return;
    if (identical(node, _rail)) return;
    _focusByScreen[_screen] = node;
    _returnFromRail = node;
  }

  /// True when a node sits inside the open popup's focus scope.
  bool _inModal(FocusNode node) {
    final scope = _modalScope;
    if (scope == null) return true; // route-driven modal: scope is implicit
    if (identical(node, scope) || scope.descendants.contains(node)) return true;
    return node.ancestors.any((a) => identical(a, scope));
  }

  /// Opens a popup. Focus goes to [safeFocus] when one is supplied — confirm
  /// dialogs pass the non-destructive button — and B/pop returns it to the
  /// element that opened the popup.
  void openModal({
    required FocusNode opener,
    FocusScopeNode? scope,
    FocusNode? safeFocus,
  }) {
    if (_modalDepth == 0) {
      _opener = opener;
      _modalScope = scope;
    }
    _modalDepth++;
    // An explicit safe button is focused now. Route-driven dialogs have their
    // own FocusScope with autofocus, so there is nothing to focus here.
    _modalFocus = safeFocus;
    _repeater.stop();
    if (_modalFocus != null) _focus(_modalFocus!);
    notifyListeners();
  }

  /// Closes the top popup and restores the opener's focus.
  void closeModal() {
    if (_modalDepth == 0) return;
    _modalDepth--;
    if (_modalDepth == 0) {
      final opener = _opener;
      _opener = null;
      _modalFocus = null;
      _modalScope = null;
      if (opener != null) _focus(opener);
    }
    notifyListeners();
  }

  /// Moves focus one step in [dir]. This is the single path used by arrows,
  /// the d-pad and the analogue stick, so there is only ever one focus.
  /// Returns true when focus actually moved.
  bool move(TraversalDirection dir, {FocusNode? from}) {
    lastDirection = dir;
    final focus = from ?? FocusManager.instance.primaryFocus;
    if (focus == null) {
      final start = _focusByScreen[_screen] ?? _rail;
      if (start != null) {
        _focus(start);
        return true;
      }
      FocusManager.instance.rootScope.nextFocus();
      return true;
    }

    if (modalOpen && !_inModal(focus)) {
      final target = _modalFocus;
      if (target != null) _focus(target);
      // A route popup keeps its own autofocus; do not pull focus back out.
      return true;
    }

    // Left at the first column leaves the screen for the rail; right on the
    // rail comes back to wherever the screen was.
    if (identical(focus, _rail)) {
      if (dir == TraversalDirection.right) {
        final back = _returnFromRail ?? _focusByScreen[_screen];
        if (back != null) {
          _focus(back);
          return true;
        }
      }
      _bump(dir, focus);
      return false;
    }

    // A widget that browses on its own (the 3D shelf) overrides the
    // directional intent. Flutter's default focusInDirection ignores that
    // custom action and returns false, so find it the way the arrow keys do.
    final ctx = focus.context;
    final intent = DirectionalFocusIntent(dir);
    final action = ctx == null
        ? null
        : Actions.maybeFind<DirectionalFocusIntent>(ctx, intent: intent);
    bool moved;
    if (action != null && action is! DirectionalFocusAction) {
      Actions.invoke(ctx!, intent);
      moved = true;
    } else {
      moved = focus.focusInDirection(dir);
    }
    if (moved) {
      remember(focus);
      return true;
    }

    if (dir == TraversalDirection.left && _rail != null) {
      _focus(_rail!);
      return true;
    }
    if (dir == TraversalDirection.up &&
        _selectedCover != null &&
        (_selectedCover!.context?.mounted ?? false)) {
      // Coming up from the dock lands on the selected cover, not the first.
      // A different look can leave the shelf unmounted; then there is nothing
      // to return to and the row-end bump below is the honest answer.
      _focus(_selectedCover!);
      return true;
    }
    _bump(dir, focus);
    return false;
  }

  void _bump(TraversalDirection dir, FocusNode node) {
    final id = _ids[node];
    if (id == null) return;
    edge.value = EdgeSignal(id, dir, ++_edgeSequence);
  }

  /// Starts the held-repeat timer for a direction. The first step happens
  /// now; the timer produces the 380 ms / 110 ms repeats.
  void startRepeat(TraversalDirection dir, {FocusNode? from}) {
    lastDirection = dir;
    move(dir, from: from);
    _repeater.start();
  }

  void stopRepeat() => _repeater.stop();

  /// Directional intent of an analogue stick, or null inside the 0.55 dead
  /// zone. Gamepad axes report down and right as positive.
  static TraversalDirection? directionFromStick(double dx, double dy) {
    if (dx.abs() < analogDeadZone && dy.abs() < analogDeadZone) return null;
    if (dx.abs() >= dy.abs()) {
      return dx >= 0 ? TraversalDirection.right : TraversalDirection.left;
    }
    return dy >= 0 ? TraversalDirection.down : TraversalDirection.up;
  }

  /// Arrow keys are handled here rather than left to Flutter's own key repeat,
  /// so the timing is the design's 380/110 rather than the OS rate. Other keys
  /// are left alone for the existing shortcuts and activation intents.
  KeyEventResult onKey(KeyEvent event, {FocusNode? from}) {
    if (event is KeyDownEvent) {
      InputMode.shared.noteKeyboard();
      final dir = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        LogicalKeyboardKey.arrowRight => TraversalDirection.right,
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        _ => null,
      };
      if (dir != null) {
        // Track the held key ourselves: KeyEvent has no `repeat` flag, and
        // the OS's own repeat rate is not the design's 380/110 cadence.
        if (_heldKeys.add(event.logicalKey)) startRepeat(dir, from: from);
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(event.logicalKey);
      stopRepeat();
    }
    return KeyEventResult.ignored;
  }

  /// Test-only reset: the singleton outlives individual widget tests.
  void reset() {
    stopRepeat();
    _nodes.clear();
    _ids.clear();
    _focusByScreen.clear();
    _screen = 'library';
    _rail = null;
    _returnFromRail = null;
    _selectedCover = null;
    _opener = null;
    _modalFocus = null;
    _modalScope = null;
    _modalDepth = 0;
    lastDirection = null;
    _heldKeys.clear();
    edge.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _repeater.stop();
    edge.dispose();
    super.dispose();
  }
}

/// Watches Navigator for popups (dialogs, sheets and context menus are all
/// [PopupRoute]s here). Entering one traps focus; leaving it returns focus to
/// the element that opened it, including when B pops the route.
class FocusRouteObserver extends NavigatorObserver {
  /// Used only when a popup is pushed before anything has been focused.
  final _fallbackOpener = FocusNode(debugLabel: 'popup opener');

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PopupRoute) {
      FocusOwner.shared.openModal(
        opener: FocusManager.instance.primaryFocus ?? _fallbackOpener,
      );
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is PopupRoute) FocusOwner.shared.closeModal();
  }
}

final FocusRouteObserver focusRouteObserver = FocusRouteObserver();

/// Lets a controller drive every menu: d-pad moves the single focus, A
/// activates it, B goes back. Works with any widget Flutter can focus and
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
  void Function()? _cancelAxis;

  @override
  void initState() {
    super.initState();
    _cancel = (widget.subscribe ?? GamepadService.shared.onButton)(_onPad);
    // A test supplies its own button stream; only the real service has an
    // axis stream to subscribe to.
    if (widget.subscribe == null) {
      _cancelAxis = GamepadService.shared.onAxis(_onAxis);
    }
  }

  @override
  void dispose() {
    _cancel?.call();
    _cancelAxis?.call();
    FocusOwner.shared.stopRepeat();
    super.dispose();
  }

  void _onAxis(GamepadAxisEvent e) {
    if (!padNavigationEnabled.value) return;
    final dir = switch (e.axis) {
      'lx' => FocusOwner.directionFromStick(e.value, 0),
      'ly' => FocusOwner.directionFromStick(0, e.value),
      _ => null,
    };
    if (dir != null) {
      InputMode.shared.notePadActivity();
      FocusOwner.shared.move(dir);
    }
  }

  void _onPad(GamepadEvent e) {
    InputMode.shared.notePadActivity();
    if (!e.pressed || !padNavigationEnabled.value) {
      if (!e.pressed) FocusOwner.shared.stopRepeat();
      return;
    }
    final owner = FocusOwner.shared;
    final dir = switch (e.code) {
      'up' => TraversalDirection.up,
      'down' => TraversalDirection.down,
      'left' => TraversalDirection.left,
      'right' => TraversalDirection.right,
      _ => null,
    };
    if (dir != null) {
      owner.startRepeat(dir);
      return;
    }
    switch (e.code) {
      case 'a':
      case 'start':
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      case 'b':
        widget.navigatorKey.currentState?.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
