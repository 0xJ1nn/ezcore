import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controls/control_layout.dart';
import '../controls/control_overlay.dart';
import '../controls/layout_editor.dart';
import '../controls/layout_store.dart';
import '../controls/retro_keys.dart';
import '../emu/player_controller.dart';
import '../emu/process_session_backend.dart';
import '../models/game_entry.dart';
import '../services/bios_check.dart';
import '../services/core_discovery.dart';
import '../services/core_staging.dart';
import '../services/core_system_data.dart';
import '../services/cover_art.dart';
import '../services/gamepad.dart';
import '../services/human_time.dart';
import '../services/local_data_dir.dart';
import '../services/pad_mapping.dart';
import '../services/repo_layout.dart';
import '../services/runtime_loader.dart';
import '../services/scoped_files.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../state/save_sync.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_overlays.dart';
import '../widgets/orbit_widgets.dart';
import '../widgets/pad_navigator.dart';
import 'cheats_screen.dart';

/// The autosave slot's id (see `launch.dart`; repeated here so this screen
/// does not import the launcher that opens it).
const _autoSlot = 'auto';

/// Capture/test seam: a fixed picture and session so the design-parity
/// harness can render the stage without booting a native core.
///
/// Production leaves this null and every pixel comes from the running
/// session — the same seam [ImportScreen] uses for its scripted scan.
@visibleForTesting
class PlayerPreview {
  const PlayerPreview({
    this.frame,
    this.thumbnail,
    this.sessionMinutes = 0,
    this.touchControls,
  });

  /// The picture a core would have produced.
  final ui.Image? frame;

  /// A still for the pause sheet, where the design shows a 4:3 thumbnail
  /// rather than the game's own shape. Falls back to [frame].
  final ui.Image? thumbnail;

  /// Minutes this session has been running, for the pause panel's subtitle.
  final int sessionMinutes;

  /// Forces the touch layer on or off, so the capture pass can render the
  /// phone states on a desktop test runner.
  final bool? touchControls;
}

/// Orbit Player — a black stage with the game picture on it, a glass HUD
/// chip that fades after five seconds, and the "Take a breather" pause layer
/// (the picture recedes, the menu arrives). All emulation wiring preserved:
/// verified core launch, worker frames, PCM, pause, quick-save, fast-forward,
/// screenshot, touch pad, cheats, save/load, reset.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.gameId,
    required this.state,
    this.initialSlot,
    this.preview,
  });
  final String gameId;
  final AppState state;

  /// Save slot to restore right after boot (Resume, or a chosen save).
  final String? initialSlot;

  /// Capture/test seam; see [PlayerPreview].
  final PlayerPreview? preview;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  final player = PlayerController();
  final _scoped = createScopedFiles();
  final _gamepads = GamepadService.shared;
  VoidCallback? _cancelPad;
  VoidCallback? _cancelAxis;

  /// Staged vault cores (populated at startup by [CoreStagingService]).
  static String? _vaultCoresRoot() {
    final vault = CoreStagingService.vaultDir();
    return vault.existsSync() ? vault.path : null;
  }

  /// Release-bundle cores — the read-only fallback when staging hasn't run
  /// (or the vault was cleared): macOS `<app>/Contents/Resources/ezcore/cores`.
  static String? _bundledCoresRoot() {
    final roots = RepoLayout.bundledCoreRoots(
      executablePath: Platform.resolvedExecutable,
    );
    return roots.isEmpty ? null : roots.first;
  }

  bool get paused => player.paused;
  bool get fastForward => player.fastForward;

  /// A session the UI can draw: a real one, or the capture's preview.
  bool get _running => player.running || widget.preview != null;

  /// The picture on the stage, from the core or the capture fixture.
  ui.Image? get _frame => player.frame ?? widget.preview?.frame;

  /// On-screen controls. On by default where touch is the main input,
  /// off on desktop (keyboard and pads); the player can flip it any time.
  bool padVisible = true;
  final _overlayKey = GlobalKey<ControlOverlayState>();
  late final _layouts = LayoutStore(widget.state);
  bool _menuOpen = false;
  bool _menuWasPaused = false;
  final _stageFocus = FocusNode(debugLabel: 'player-stage');
  final _resumeFocus = FocusNode(debugLabel: 'pause-resume');
  List<SaveSlot> _slots = const [];
  String? _launchToast;
  Timer? _toastTimer;
  Timer? _hudTimer;
  bool _hudVisible = true;
  late final DateTime _openedAt;
  String? launchError;
  bool leaving = false;
  late final Future<void> opening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openedAt = DateTime.now();
    player.addListener(_refresh);
    // The game owns the controller while it runs; the menu navigator
    // gets it back while the pause menu or an editor is open.
    padNavigationEnabled.value = false;
    _cancelPad = _gamepads.onButton(_onPad);
    _cancelAxis = _gamepads.onAxis((e) {
      final r = e.retro;
      if (r == null || _menuOpen) return;
      _action(() => player.analog(0, r.$1, r.$2, (e.value * 32767).round()));
    });
    padVisible =
        widget.preview?.touchControls ??
        widget.state.settings['touchOverlay'] as bool? ??
        (Platform.isAndroid || Platform.isIOS);
    _restartHudTimer();
    unawaited(_loadSlots());
    opening = widget.preview != null ? Future<void>.value() : _launch();
    if (widget.preview != null) {
      final game = widget.state.games
          .where((g) => g.id == widget.gameId)
          .firstOrNull;
      _showLaunchToast(
        widget.initialSlot != null
            ? 'Picked up where you left off'
            : 'Starting ${game?.title ?? 'game'}',
      );
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get launching =>
      launchError == null &&
      player.error == null &&
      !_running &&
      _frame == null;

  /// The HUD chip shows itself for five seconds after the picture appears.
  void _restartHudTimer() {
    _hudTimer?.cancel();
    if (!_hudVisible) setState(() => _hudVisible = true);
    _hudTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  Future<void> _loadSlots() async {
    try {
      final slots = await widget.state.saves.list(widget.gameId);
      // Autosave, then the numbered slots newest-first, then recovered
      // crash-safe snapshots at the end of the strip.
      int rank(SaveSlot s) => s.id == _autoSlot ? 0 : 1;
      slots.sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final aCrash = a.id.startsWith('crash');
        final bCrash = b.id.startsWith('crash');
        if (aCrash != bCrash) return aCrash ? 1 : -1;
        if (a.id == 'slot0' && b.id != 'slot0') return -1;
        if (b.id == 'slot0' && a.id != 'slot0') return 1;
        return b.modified.compareTo(a.modified);
      });
      if (mounted) setState(() => _slots = slots);
    } catch (_) {
      // The strip is display metadata; a read failure must not block play.
    }
  }

  Future<void> _launch() async {
    try {
      final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
      widget.state.recordPlay(game.id);
      final manifests = widget.state.registry.catalog.where(
        (m) => m.id == game.coreId,
      );
      if (manifests.isEmpty) {
        throw StateError('Selected core is not in the catalog');
      }
      final manifest = manifests.single;
      if (!manifest.extensions.contains(game.extension)) {
        throw StateError('Core does not support this content');
      }
      final bios = await BiosCheck().check(manifest);
      if (!bios.satisfied) {
        throw StateError(bios.guidance);
      }
      final root =
          widget.state.settings['coreDirectory'] as String? ??
          Platform.environment['EZCORE_CORES_DIR'] ??
          _vaultCoresRoot() ??
          _bundledCoresRoot() ??
          RepoLayout.stagedCoresRoot(
            executablePath: Platform.resolvedExecutable,
          ) ??
          RepoLayout.coresRoot(executablePath: Platform.resolvedExecutable) ??
          RepoLayout.coresRoot() ??
          'native/cores';
      final corePath = await CoreDiscovery(
        Directory(root),
      ).verifiedPath(manifest);
      if (corePath == null) {
        throw StateError('No verified core installed for this platform');
      }
      // Sandboxed hosts grant ROM access only while held (macOS bookmarks;
      // passthrough elsewhere). The worker copies ROM bytes at open, so
      // holding for the open call is sufficient.
      await _scoped.withAccess(game.filePath, () async {
        if (!await File(game.filePath).exists()) {
          throw StateError('Content file does not exist');
        }
        if (!mounted || leaving) return;
        final data = await PlatformLocalDataDirProvider().localDataDir();
        final system = await Directory(
          '${data.path}/system',
        ).create(recursive: true);
        // The core's own data (core system data: Dolphin's Sys, PPSSPP's assets),
        // copied from beside the installed core once per core version.
        final systemData = await copySystemData(
          from: Directory('${File(corePath).parent.path}/system'),
          to: system,
          coreId: manifest.id,
          version: manifest.version,
          declared: manifest.systemData,
          biosFiles: manifest.biosFiles,
        );
        if (systemData.errors.isNotEmpty) {
          throw StateError(
            "This core's own data files are missing or invalid "
            '(${systemData.errors.first}). Reinstall the core.',
          );
        }
        for (final w in systemData.warnings) {
          debugPrint('ezcore: $w');
        }
        // Per-game SRAM dir: cores name battery files freely (some use
        // fixed names), so a shared dir would corrupt saves across games.
        final saves = await Directory(
          '${data.path}/sram/${game.id}',
        ).create(recursive: true);
        if (!mounted || leaving) return;
        final runtimeRef = await resolveRuntimeRef();
        // Crash protection (crash containment): off by default. When on, the core
        // runs in a separate helper process, so a crash ends only the game.
        // Loud, not silent, when the helper is missing: the user asked for
        // protection, so never quietly run without it.
        if (widget.state.settings['crashContainment'] == true) {
          final host = resolveCoreHostPath(runtimeRef);
          if (host == null) {
            throw StateError(
              'Crash protection is on, but its helper (ezcore_core_host) '
              'is not installed beside the runtime. Turn it off in '
              'Settings > Emulation, or reinstall ezCORE.',
            );
          }
          player.useBackend(ProcessSessionBackend(hostPath: host));
        }
        await player.open(
          runtimeRef: runtimeRef,
          corePath: corePath,
          contentPath: File(game.filePath).absolute.path,
          systemDir: system.path,
          saveDir: saves.path,
          coreOptions: widget.state.coreOptionsFor(
            coreId: manifest.id,
            gameId: game.id,
          ),
        );
      });
      if (!mounted || leaving) return;
      // Session-start prefs (documented in Settings → Audio/Emulation).
      final prefs = widget.state.settings;
      player.muted = prefs['muted'] == true;
      player.volume =
          int.tryParse('${prefs['volume'] ?? '80'}')?.clamp(0, 100) ?? 80;
      player.ffFrames =
          int.tryParse('${prefs['ffFrames'] ?? '4'}')?.clamp(1, 8) ?? 4;
      await _applyCheats();
      if (_keyboardFirst && mounted) {
        orbitToast(
          context,
          'Keyboard and mouse go to the game. F12 opens the menu.',
        );
      }
      final slot = widget.initialSlot;
      if (slot != null && mounted && !leaving) {
        await _action(
          () => player.restore(widget.state.saves, game.id, slot),
          'Loaded $slot',
        );
      }
      if (mounted) {
        _showLaunchToast(
          slot != null
              ? 'Picked up where you left off'
              : 'Starting ${game.title}',
        );
        await _loadSlots();
      }
    } catch (e) {
      if (mounted) setState(() => launchError = 'Launch failed: $e');
    }
  }

  void _showLaunchToast(String message) {
    _toastTimer?.cancel();
    setState(() => _launchToast = message);
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _launchToast = null);
    });
  }

  /// Pushes stored cheats into the live session. Silent unless the runtime
  /// cannot dispatch an index or the call itself fails.
  Future<void> _applyCheats() async {
    if (!mounted || leaving || !player.running) return;
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    final cheats = widget.state.cheatsFor(game.id);
    if (cheats.isEmpty) return;
    try {
      final notDispatched = await player.applyCheats(cheats);
      if (notDispatched.isNotEmpty && mounted) {
        orbitToast(
          context,
          '${notDispatched.length} cheat(s) could not be dispatched',
        );
      }
    } catch (e) {
      if (mounted) orbitToast(context, 'Cheats did not apply: $e');
    }
  }

  Future<void> _refreshStateCount() async {
    try {
      final slots = await widget.state.saves.list(widget.gameId);
      widget.state.setStateCount(widget.gameId, slots.length);
    } catch (_) {
      // Count is display metadata; a listing failure must not break saves.
    }
  }

  Future<void> _action(
    Future<void> Function() operation, [
    String? success,
  ]) async {
    try {
      await operation();
      if (mounted && success != null) orbitToast(context, success);
    } catch (e) {
      if (mounted) orbitToast(context, e.toString());
    }
  }

  Future<void> _exit() async {
    if (leaving) return;
    leaving = true;
    await opening;
    if (widget.state.settings['autosave'] != false) {
      await _autoSave();
    }
    await _action(player.close);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // The worker's pause path releases every button, so the poller's view
      // of what it has emitted is now stale: forget it here or a control
      // still held on return produces no transition and never re-sent.
      _gamepads.forgetHeld();
      unawaited(_action(() => player.setPaused(true)));
      if (widget.state.settings['autosave'] != false) {
        unawaited(_autoSave());
      }
    }
  }

  @override
  void dispose() {
    padNavigationEnabled.value = true;
    leaving = true;
    _cancelPad?.call();
    _cancelAxis?.call();
    _hudTimer?.cancel();
    _toastTimer?.cancel();
    _stageFocus.dispose();
    _resumeFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(_refresh);
    unawaited(opening.whenComplete(player.dispose));
    super.dispose();
  }

  Future<void> _screenshot() async {
    final image = player.frame?.clone();
    if (image == null) throw StateError('No video frame yet');
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed');
      final data = await PlatformLocalDataDirProvider().localDataDir();
      final folder = await Directory(
        '${data.path}/screenshots',
      ).create(recursive: true);
      final file = File(
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      // Pin a copy as this game's cover so the library shows real captures.
      try {
        final game = widget.state.games.firstWhere(
          (g) => g.id == widget.gameId,
        );
        final art = File('${data.path}/art/${game.id}.png');
        await art.parent.create(recursive: true);
        await file.copy(art.path);
        invalidateCoverFile(game.id);
      } catch (_) {
        // Cover pinning is best-effort; the screenshot itself is saved.
      }
      if (mounted) orbitToast(context, 'Screenshot saved');
    } finally {
      image.dispose();
    }
  }

  Future<void> _saveMoment() async {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    await player.save(widget.state.saves, widget.gameId, 'slot0');
    await player.save(widget.state.saves, widget.gameId, 'slot-$stamp');
    await _refreshStateCount();
    await _loadSlots();
  }

  Future<void> _autoSave() async {
    if (!player.running || player.error != null || launchError != null) {
      return;
    }
    try {
      await player.save(widget.state.saves, widget.gameId, _autoSlot);
      await _refreshStateCount();
    } catch (_) {
      // Autosave is best-effort; explicit saves still report errors.
    }
  }

  void _buzz() {
    if (widget.state.settings['haptics'] == false) return;
    try {
      unawaited(HapticFeedback.lightImpact());
    } catch (_) {
      // No haptics channel on this platform; touch still works.
    }
  }

  final _chord = PadChord();
  late final _padMap = PadMapping(widget.state);

  /// Controller input during play, through the user's button mapping.
  /// Select + Start together opens the pause menu (see [PadChord]).
  void _onPad(GamepadEvent e) {
    switch (_chord.feed(e.code, e.pressed)) {
      case ChordResult.openMenu:
        for (final b in PadChord.buttons) {
          final id = _padMap.retroIdFor(b);
          if (id != null) _action(() => player.button(id, false));
        }
        unawaited(_openMenu());
        return;
      case ChordResult.swallow:
        return;
      case ChordResult.pass:
        break;
    }
    if (_menuOpen) return;
    final id = _padMap.retroIdFor(e.code);
    if (id != null) _action(() => player.button(id, e.pressed));
  }

  Future<void> _hostInput(String input) async {
    switch (input) {
      case 'menu':
        await _openMenu();
      case 'fast_forward':
        setState(() => player.fastForward = !fastForward);
    }
  }

  /// Keyboard-and-mouse systems (DOS, adventures, computers): every key
  /// goes to the core and the pause menu moves from Esc to F12.
  bool get _keyboardFirst {
    final g = widget.state.games
        .where((g) => g.id == widget.gameId)
        .firstOrNull;
    return g != null && keyboardFirstSystems.contains(g.system);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final kbFirst = _keyboardFirst;
    final menuKey = kbFirst
        ? LogicalKeyboardKey.f12
        : LogicalKeyboardKey.escape;
    if (event.logicalKey == menuKey) {
      if (event is KeyDownEvent) {
        if (_menuOpen) {
          unawaited(_closeMenu());
        } else {
          unawaited(_openMenu());
        }
      }
      return KeyEventResult.handled;
    }
    // The pause menu owns the keyboard while it is open: arrows move focus,
    // Enter selects, Esc closes. Nothing reaches the core.
    if (_menuOpen) return KeyEventResult.ignored;
    // P pauses on console systems (handoff §4.2). A core that reads the
    // keyboard keeps every key, so keyboard-first systems skip this.
    if (!kbFirst && event.logicalKey == LogicalKeyboardKey.keyP) {
      if (event is KeyDownEvent) unawaited(_openMenu());
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    final down = event is KeyDownEvent;
    // Every key reaches a core that reads the keyboard; cores that don't,
    // ignore it.
    final retroKey = retroKeys[event.logicalKey];
    if (retroKey != null) {
      final ch = down ? (event.character?.runes.firstOrNull ?? 0) : 0;
      _action(
        () => player.key(
          retroKey,
          down,
          character: ch,
          modifiers: retroModifiers(),
        ),
      );
    }
    // Console games also get the keyboard as a pad.
    int? padId;
    if (!kbFirst) {
      padId = {
        LogicalKeyboardKey.arrowUp: 4,
        LogicalKeyboardKey.arrowDown: 5,
        LogicalKeyboardKey.arrowLeft: 6,
        LogicalKeyboardKey.arrowRight: 7,
        LogicalKeyboardKey.keyZ: 0,
        LogicalKeyboardKey.keyX: 8,
        LogicalKeyboardKey.keyA: 1,
        LogicalKeyboardKey.keyS: 9,
        LogicalKeyboardKey.keyQ: 10,
        LogicalKeyboardKey.keyW: 11,
        LogicalKeyboardKey.enter: 3,
        LogicalKeyboardKey.shiftRight: 2,
      }[event.logicalKey];
      if (padId != null) _action(() => player.button(padId!, down));
    }
    return retroKey != null || padId != null
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  int _mouseButtons = 0;

  /// Mouse over the game: motion and buttons go to the core's mouse, and the
  /// cursor position drives its pointer. Touch on the picture (when the
  /// on-screen controls are hidden) drives the pointer too.
  void _onMouse(PointerEvent e, ScreenSpec screen, Size size) {
    if (_menuOpen) return;
    final frame = _frame;
    if (frame == null || !_running) return;
    final isMouse = e.kind == PointerDeviceKind.mouse;
    if (isMouse && e.delta != Offset.zero) {
      _action(() => player.mouseMove(e.delta.dx.round(), e.delta.dy.round()));
    }
    if (isMouse) {
      const ids = {
        kPrimaryMouseButton: 2,
        kSecondaryMouseButton: 3,
        kMiddleMouseButton: 6,
      };
      final now = e is PointerUpEvent || e is PointerCancelEvent
          ? 0
          : e.buttons;
      for (final MapEntry(key: bit, value: id) in ids.entries) {
        if ((now & bit) != (_mouseButtons & bit)) {
          _action(() => player.mouseButton(id, (now & bit) != 0));
        }
      }
      _mouseButtons = now;
    }
    final at = frameCoordinate(
      screen,
      size,
      frame.width / frame.height,
      e.localPosition,
    );
    if (at != null) {
      final (x, y) = toPointer(at);
      final pressed =
          e is! PointerUpEvent &&
          e is! PointerCancelEvent &&
          (isMouse ? (e.buttons & kPrimaryMouseButton) != 0 : e.down);
      _action(() => player.pointer(x, y, pressed));
    }
  }

  bool get _reduceMotion {
    if (widget.state.settings['motion'] == false) return true;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    return PopScope(
      canPop: false,
      // Back (gesture or button) opens the pause menu; leaving the game is
      // a deliberate choice there, so a stray swipe never loses progress.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_menuOpen) {
          unawaited(_closeMenu());
        } else {
          unawaited(_openMenu());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _stageFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => _stage(game, c.biggest),
            ),
          ),
        ),
      ),
    );
  }

  /// Where the picture lands, in stage coordinates, for this build.
  ({Rect box, ScreenSpec screen}) _placement(
    Size size,
    ControlLayout layout,
    bool showControls,
    OrbitLayout family,
  ) {
    final frame = _frame;
    if (frame == null) {
      return (
        box: Offset.zero & size,
        screen: const ScreenSpec(rect: NormRect(0, 0, 1, 1)),
      );
    }
    ScreenSpec specFor(
      Rect box, {
      int split = 1,
      String arrange = 'stacked',
      double gap = 0,
    }) => ScreenSpec(
      rect: NormRect(
        box.left / size.width,
        box.top / size.height,
        box.width / size.width,
        box.height / size.height,
      ),
      split: split,
      arrange: arrange,
      gap: gap,
    );
    // Phone portrait: the picture runs edge to edge and keeps the game's
    // own shape. With the touch controls visible it sits above their band.
    if (family == OrbitLayout.phonePortrait) {
      var scale = size.width / frame.width;
      final maxHeight = size.height * 0.70;
      if (frame.height * scale > maxHeight) {
        scale = maxHeight / frame.height;
      }
      final pinned = showControls || _menuOpen;
      final box = Rect.fromLTWH(
        0,
        pinned
            ? size.height * 0.0664
            : (size.height - frame.height * scale) / 2,
        frame.width * scale,
        frame.height * scale,
      );
      return (
        box: box,
        screen: specFor(
          box,
          split: layout.screen.split,
          arrange: 'stacked',
          gap: 0.01,
        ),
      );
    }
    // Phone landscape: the largest integer scale that fits, clear of the
    // bottom control row.
    if (family == OrbitLayout.phoneLandscape) {
      final fit = math.min(
        size.width / frame.width,
        size.height / frame.height,
      );
      final scale = fit >= 1 ? fit.floorToDouble() : fit;
      final h = frame.height * scale;
      final top = math.max(0.0, (size.height - h - 26) / 2);
      final box = Rect.fromLTWH(
        (size.width - frame.width * scale) / 2,
        top,
        frame.width * scale,
        h,
      );
      return (
        box: box,
        screen: specFor(
          box,
          split: layout.screen.split,
          arrange: layout.screen.arrange,
          gap: layout.screen.gap,
        ),
      );
    }
    if (showControls) {
      return (
        box: layout.screen.rect.resolve(size.width, size.height),
        screen: layout.screen,
      );
    }
    // Desktop and tablet: the largest integer scale that fits, centred.
    // Only a frame larger than the stage falls back to a fractional fit.
    final fit = math.min(size.width / frame.width, size.height / frame.height);
    final scale = fit >= 1 ? fit.floorToDouble() : fit;
    final box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frame.width * scale,
      height: frame.height * scale,
    );
    return (box: box, screen: specFor(box));
  }

  /// Touch controls move into the band below the full-bleed phone picture.
  /// The design's phone boards use their own geometry; a layout the player
  /// has edited is left exactly as they saved it.
  ControlLayout _phoneControls(ControlLayout base, OrbitLayout family) {
    final portrait = family == OrbitLayout.phonePortrait;
    const faceIds = {
      'x',
      'y',
      'a',
      'b',
      'triangle',
      'square',
      'circle',
      'cross',
      'ga',
      'gb',
      'gc',
      'i',
      'ii',
      'fire',
    };
    final faces = base.controls.where((c) => faceIds.contains(c.id)).toList();
    var faceMinX = 0.0, faceMaxX = 1.0, faceMinY = 0.0, faceMaxY = 1.0;
    if (faces.isNotEmpty) {
      final centers = [
        for (final c in faces)
          Offset(c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2),
      ];
      faceMinX = centers.map((c) => c.dx).reduce(math.min);
      faceMaxX = centers.map((c) => c.dx).reduce(math.max);
      faceMinY = centers.map((c) => c.dy).reduce(math.min);
      faceMaxY = centers.map((c) => c.dy).reduce(math.max);
    }
    final target = portrait
        ? const Rect.fromLTRB(0.664, 0.8495, 0.882, 0.9491)
        : const Rect.fromLTRB(0.827, 0.431, 0.923, 0.554);
    double span(double lo, double hi, double at) =>
        hi == lo ? 0.5 : (at - lo) / (hi - lo);

    NormRect place(ControlSpec c) {
      final r = c.rect;
      final cx =
          target.left + span(faceMinX, faceMaxX, r.x + r.w / 2) * target.width;
      final cy =
          target.top + span(faceMinY, faceMaxY, r.y + r.h / 2) * target.height;
      final a = c.id == 'a' || c.id == 'circle';
      final size = portrait ? (a ? 0.1128 : 0.1077) : 0.0545;
      final h = portrait ? (a ? 0.0521 : 0.0498) : 0.1179;
      return NormRect(cx - size / 2, cy - h / 2, size, h);
    }

    final controls = <ControlSpec>[];
    for (final c in base.controls) {
      if (c.id == 'menu') {
        if (!portrait) {
          controls.add(
            c.copyWith(rect: const NormRect(0.461, 0.892, 0.083, 0.067)),
          );
        }
        continue;
      }
      switch (c.id) {
        case 'l':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.0385, 0.7761, 0.241, 0.0450)
                  : const NormRect(0.0237, 0.0538, 0.1386, 0.0923),
            ),
          );
        case 'r':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.7205, 0.7761, 0.241, 0.0450)
                  : const NormRect(0.8365, 0.0538, 0.1386, 0.0923),
            ),
          );
        case 'l2':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.0385, 0.735, 0.241, 0.0403)
                  : const NormRect(0.0237, 0.155, 0.1386, 0.0923),
            ),
          );
        case 'r2':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.7205, 0.735, 0.241, 0.0403)
                  : const NormRect(0.8365, 0.155, 0.1386, 0.0923),
            ),
          );
        case 'z':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.0385, 0.735, 0.241, 0.0403)
                  : const NormRect(0.0237, 0.155, 0.1386, 0.0923),
            ),
          );
        case 'dpad':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.073, 0.830, 0.303, 0.140)
                  : const NormRect(0.0367, 0.3333, 0.1528, 0.3282),
            ),
          );
        case 'select':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.331, 0.942, 0.164, 0.0332)
                  : const NormRect(0.378, 0.892, 0.0687, 0.067),
            ),
          );
        case 'start':
          controls.add(
            c.copyWith(
              rect: portrait
                  ? const NormRect(0.526, 0.942, 0.144, 0.0332)
                  : const NormRect(0.558, 0.892, 0.0675, 0.067),
            ),
          );
        default:
          if (faceIds.contains(c.id)) {
            controls.add(c.copyWith(rect: place(c)));
          } else {
            controls.add(c);
          }
      }
    }
    return ControlLayout(
      id: base.id,
      name: base.name,
      systems: base.systems,
      orientation: base.orientation,
      screen: base.screen,
      controls: controls,
      shell: base.shell,
      opacity: base.opacity,
    );
  }

  Widget _stage(GameEntry game, Size size) {
    final portrait = size.height > size.width;
    final family = Layout.ofSize(
      size,
      portrait ? Orientation.portrait : Orientation.landscape,
    );
    final layout = _layouts.resolve(
      game.system,
      portrait: portrait,
      coreId: game.coreId,
    );
    final controlsLayout =
        Layout.isPhone(family) && _layouts.custom(layout.id) == null
        ? _phoneControls(layout, family)
        : layout;
    final showControls = padVisible && _running && !_menuOpen;
    final frame = _frame;
    final failed = launchError ?? player.error;
    final place = _placement(size, layout, showControls, family);
    // The painter works inside the picture's own box, so split screens
    // (a DS) keep their arrangement at any scale.
    final localSpec = ScreenSpec(
      rect: const NormRect(0, 0, 1, 1),
      split: place.screen.split,
      arrange: place.screen.arrange,
      gap: place.screen.gap,
    );
    final kind = switch (family) {
      OrbitLayout.phonePortrait => _PauseKind.sheet,
      OrbitLayout.phoneLandscape => _PauseKind.compact,
      _ => _PauseKind.panel,
    };
    final metrics = _PauseMetrics.of(kind, size);
    final reduce = _reduceMotion;
    final phone = Layout.isPhone(family);
    final hasMenuControl = controlsLayout.controls.any((c) => c.id == 'menu');

    // Mouse always; touch only when the on-screen controls are hidden (the
    // overlay owns touch otherwise, and routes picture touches itself).
    void route(PointerEvent e) {
      if (e.kind == PointerDeviceKind.mouse || !showControls) {
        _onMouse(e, place.screen, size);
      }
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _restartHudTimer();
        route(e);
      },
      onPointerMove: route,
      onPointerHover: route,
      onPointerUp: route,
      onPointerCancel: route,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _menuOpen ? 1 : 0),
        duration: reduce ? const Duration(milliseconds: 160) : Tokens.moveDur,
        curve: Tokens.ease,
        builder: (context, t, _) {
          final dimmed = t > 0.001;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (frame != null && !phone)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AmbientPainter(frame, dimmed ? 0.2 : 0.25),
                  ),
                ),
              if (frame != null)
                _frameCard(
                  size,
                  place.box,
                  localSpec,
                  frame,
                  metrics,
                  t,
                  reduce,
                ),
              if (frame == null || failed != null)
                Positioned.fromRect(
                  rect: place.box,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: failed != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  failed,
                                  textAlign: TextAlign.center,
                                  style: Tokens.body(
                                    size: 13,
                                    color: Tokens.danger,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OrbitSecondary(
                                  label: 'Back to library',
                                  onPressed: _exit,
                                ),
                              ],
                            )
                          : launching
                          ? const CircularProgressIndicator(
                              color: Tokens.accent,
                            )
                          : Text(
                              'Waiting for video…',
                              style: Tokens.body(size: 12, color: Tokens.muted),
                            ),
                    ),
                  ),
                ),
              if (showControls)
                Positioned.fill(
                  child: ControlOverlay(
                    key: _overlayKey,
                    layout: controlsLayout,
                    onInput: (input, pressed) {
                      final id = retroPadId(input);
                      if (id != null) _action(() => player.button(id, pressed));
                    },
                    onHostInput: _hostInput,
                    onTouch: _buzz,
                    toFrame: (p, sz) => frame == null
                        ? null
                        : frameCoordinate(
                            place.screen,
                            sz,
                            frame.width / frame.height,
                            p,
                          ),
                    onPicture: (at, pressed) {
                      final (x, y) = toPointer(at);
                      _action(() => player.pointer(x, y, pressed));
                    },
                  ),
                ),
              if (!showControls || !hasMenuControl)
                Positioned(
                  left: family == OrbitLayout.phonePortrait ? 0 : 28,
                  right: family == OrbitLayout.phonePortrait ? 0 : null,
                  top: family == OrbitLayout.phonePortrait ? 12 : 24,
                  child: IgnorePointer(
                    ignoring: !_hudVisible || dimmed,
                    child: AnimatedOpacity(
                      duration: reduce
                          ? const Duration(milliseconds: 160)
                          : Tokens.ambientDur,
                      opacity: _hudVisible && !dimmed ? 1 : 0,
                      child: Center(
                        heightFactor: 1,
                        child: _PlayerHud(
                          glyph: _pauseGlyph,
                          onTap: _openMenu,
                          compact: family == OrbitLayout.phonePortrait,
                        ),
                      ),
                    ),
                  ),
                ),
              if (fastForward || player.audioError != null)
                Positioned(
                  top: 72,
                  left: 28,
                  child: Text(
                    player.audioError ?? 'Fast-forward',
                    style: Tokens.body(
                      size: 12,
                      color: player.audioError != null
                          ? Tokens.danger
                          : Tokens.muted,
                    ),
                  ),
                ),
              if (t > 0)
                _pauseLayer(game, size, place.box, metrics, t, reduce: reduce),
              if (!_menuOpen)
                Positioned(
                  top: family == OrbitLayout.phonePortrait ? 56 : 28,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: Tokens.baseDur,
                        child: _launchToast == null
                            ? const SizedBox.shrink()
                            : _PlayerToast(
                                key: ValueKey(_launchToast),
                                message: _launchToast!,
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The key the pause action answers to, in the input's own glyphs.
  String get _pauseGlyph =>
      GamepadService.shared.connectedPad != null ? '+' : 'P';

  Widget _frameCard(
    Size stage,
    Rect base,
    ScreenSpec local,
    ui.Image image,
    _PauseMetrics metrics,
    double t,
    bool reduce,
  ) {
    if (metrics.kind == _PauseKind.sheet) {
      final target = metrics.sheetFrame(stage);
      final rect = Rect.lerp(base, target, t)!;
      final thumb = widget.preview?.thumbnail ?? image;
      return Positioned.fromRect(
        key: const Key('player-frame'),
        rect: rect,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x332A353A)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                offset: Offset(0, 18),
                blurRadius: 42,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: GamePicturePainter(image, local)),
              Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: CustomPaint(painter: _CoverPicturePainter(thumb)),
              ),
            ],
          ),
        ),
      );
    }
    final target = metrics.recede(base, stage, t, reduce: reduce);
    final offset = target.center - base.center;
    final radius = 18 * t;
    Widget card = Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(radius),
        border: t > 0.001 ? Border.all(color: const Color(0xFF2A353A)) : null,
        boxShadow: t > 0.001
            ? [
                BoxShadow(
                  color: Color.lerp(
                    Colors.transparent,
                    const Color(0xCC000000),
                    t,
                  )!,
                  offset: const Offset(0, 40),
                  blurRadius: 100,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: GamePicturePainter(image, local)),
    );
    if (t > 0.001) {
      // The whole card recedes: the picture keeps its own pixels and the
      // layer is scaled, so it stays clean instead of re-sampling nearest.
      // Translation stays outside the perspective: CSS applies it after
      // the projection, so the card's centre lands where it was aimed.
      card = Transform.translate(
        offset: offset,
        child: Transform(
          key: const Key('player-frame-recede'),
          alignment: Alignment.center,
          transform: _recedeMatrix(target.scale, target.tilt),
          child: card,
        ),
      );
    }
    return Positioned.fromRect(
      key: const Key('player-frame'),
      rect: base,
      child: card,
    );
  }

  /// CSS `scale(...) perspective(1600px) rotateY(θ)` over the card's own
  /// centre.
  static Matrix4 _recedeMatrix(double scale, double tilt) => Matrix4.identity()
    ..scaleByDouble(scale, scale, 1, 1)
    ..setEntry(3, 2, 1 / 1600)
    ..rotateY(tilt);

  // ---- Pause ----

  String _coreName(GameEntry game) {
    final manifest = widget.state.registry.catalog
        .where((m) => m.id == game.coreId)
        .firstOrNull;
    if (manifest != null && manifest.name.isNotEmpty) return manifest.name;
    if (game.coreId.isNotEmpty) return game.coreId;
    return 'No core';
  }

  int get _sessionMinutes =>
      widget.preview?.sessionMinutes ??
      DateTime.now().difference(_openedAt).inMinutes;

  List<_MenuEntry> _menuEntries(GameEntry game) {
    final on = widget.state.cheatsFor(game.id).where((c) => c.enabled).length;
    final saved = _slots.length;
    return [
      const _MenuEntry('resume', Symbols.playArrow, 'Resume', 'Resume'),
      _MenuEntry(
        'save',
        Symbols.bookmarkAdd,
        'Save snapshot',
        'Save',
        enabled: _running,
      ),
      _MenuEntry(
        'load',
        Symbols.history,
        'Load snapshot',
        'Load',
        hint: saved == 1 ? '1 saved' : '$saved saved',
        enabled: _running && saved > 0,
      ),
      _MenuEntry(
        'cheats',
        Symbols.bolt,
        'Cheats',
        'Cheats',
        hint: on > 0 ? '$on on' : null,
      ),
      const _MenuEntry(
        'controls',
        Symbols.sportsEsports,
        'Controls',
        'Controls',
      ),
      _MenuEntry(
        'restart',
        Symbols.restartAlt,
        'Restart game',
        'Restart',
        enabled: _running,
      ),
      const _MenuEntry('quit', Symbols.logout, 'Quit to library', 'Quit'),
    ];
  }

  Widget _pauseLayer(
    GameEntry game,
    Size size,
    Rect base,
    _PauseMetrics metrics,
    double t, {
    required bool reduce,
  }) {
    final entries = _menuEntries(game);
    final system = systemLabels[game.system] ?? game.system;
    final core = _coreName(game);
    final minute = _sessionMinutes;
    final subtitle = '$system · $core · session $minute min';
    final last = _slots.isEmpty ? null : _slots.first;
    final autosave = last == null
        ? null
        : 'autosaved ${lastPlayedLabel(last.modified.millisecondsSinceEpoch).toLowerCase()}';
    final compactSubtitle =
        'Session $minute min${autosave == null ? '' : ' · $autosave'}';
    final slide = reduce ? 0.0 : 14 * (1 - t);
    final opacity = reduce ? 1.0 : t.clamp(0.0, 1.0);
    final pad = GamepadService.shared.connectedPad != null;
    final hint = _HintRow(
      hints: pad
          ? const [('A', 'Select'), ('B', 'Resume')]
          : const [('Enter', 'Select'), ('Esc', 'Resume')],
    );

    final strip = _SnapshotStrip(
      slots: _slots,
      style: switch (metrics.kind) {
        _PauseKind.panel => _SnapStyle.wide,
        _PauseKind.compact => _SnapStyle.compact,
        _PauseKind.sheet => _SnapStyle.sheet,
      },
      cardWidth: metrics.cardWidth,
      cardHeight: metrics.cardHeight,
      headingSize: metrics.kind == _PauseKind.sheet ? 15 : 18,
      gap: switch (metrics.kind) {
        _PauseKind.panel => 16.0,
        _PauseKind.compact => 11.0,
        _PauseKind.sheet => 12.0,
      },
      onLoad: _loadSlot,
    );

    final Widget panel = switch (metrics.kind) {
      _PauseKind.panel => _PausePanel(
        width: metrics.panelWidth,
        title: game.title,
        subtitle: subtitle,
        entries: entries,
        onAction: _menuAction,
        resumeFocus: _resumeFocus,
      ),
      _PauseKind.compact => _PauseCompactPanel(
        width: metrics.panelWidth,
        title: game.title,
        entries: entries,
        onAction: _menuAction,
        resumeFocus: _resumeFocus,
      ),
      _PauseKind.sheet => _PauseSheet(
        title: game.title,
        subtitle: compactSubtitle,
        entries: entries,
        onAction: _menuAction,
        resumeFocus: _resumeFocus,
        strip: strip.block(),
      ),
    };

    final snapshotHeading = metrics.kind == _PauseKind.panel
        ? Positioned(
            left: metrics.panelWidth + 50,
            top: metrics.stripTop - 3,
            right: 48,
            child: strip.heading(),
          )
        : const SizedBox.shrink();
    final snapshotCards = metrics.kind == _PauseKind.panel
        ? Positioned(
            left: metrics.panelWidth + 50,
            top: metrics.stripTop + 30,
            right: 48,
            child: strip.cards(),
          )
        : const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !_menuOpen,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (metrics.kind == _PauseKind.panel) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: metrics.panelWidth,
                child: Transform.translate(
                  offset: Offset(0, slide),
                  child: panel,
                ),
              ),
              snapshotHeading,
              snapshotCards,
              Positioned(right: 44, bottom: 20, child: hint),
            ],
            if (metrics.kind == _PauseKind.compact) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: metrics.panelWidth,
                child: Transform.translate(
                  offset: Offset(0, slide),
                  child: panel,
                ),
              ),
              Positioned(
                left: metrics.recededRect(base, size, reduce: reduce).left - 5,
                top: metrics.stripTop,
                right: 45,
                height: metrics.cardHeight,
                child: strip.cards(),
              ),
            ],
            if (metrics.kind == _PauseKind.sheet)
              Positioned(
                left: 0,
                right: 0,
                top: metrics.sheetTop,
                bottom: 0,
                child: Transform.translate(
                  offset: Offset(0, slide),
                  child: panel,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu() async {
    if (_menuOpen || leaving) return;
    _overlayKey.currentState?.releaseAll();
    // Pausing releases every button host-side, so the poller's emitted set
    // goes stale; forget it or a control still held on resume is never
    // re-sent.
    _gamepads.forgetHeld();
    _menuWasPaused = player.paused;
    if (player.running && !_menuWasPaused) {
      await _action(() => player.setPaused(true));
    }
    await _loadSlots();
    if (!mounted) return;
    padNavigationEnabled.value = true;
    _hudTimer?.cancel();
    setState(() {
      _menuOpen = true;
      _hudVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuOpen) _resumeFocus.requestFocus();
    });
  }

  /// Closes the pause layer. [resume] false leaves the session paused (the
  /// player is leaving or a dialog takes over).
  Future<void> _closeMenu({bool resume = true}) async {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    padNavigationEnabled.value = false;
    if (resume && player.running && !_menuWasPaused) {
      await _action(() => player.setPaused(false));
    }
    if (mounted) {
      _stageFocus.requestFocus();
      _restartHudTimer();
    }
  }

  Future<void> _menuAction(String id) async {
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    switch (id) {
      case 'resume':
        await _closeMenu();
      case 'save':
        await _action(_saveMoment, 'Snapshot saved');
        await _closeMenu();
      case 'load':
        await _action(
          () =>
              player.restore(widget.state.saves, widget.gameId, _loadSlotId()),
          'Snapshot loaded',
        );
        await _closeMenu();
      case 'cheats':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CheatsScreen(
              gameId: widget.gameId,
              state: widget.state,
              onCheatsChanged: _applyCheats,
            ),
          ),
        );
        padNavigationEnabled.value = true;
        if (mounted) setState(() {});
      case 'controls':
        await _controlsSheet(game);
      case 'restart':
        await _restartGame(game);
      case 'quit':
        await _quitFlow(game);
    }
  }

  String _loadSlotId() {
    if (_slots.isEmpty) return 'slot0';
    return _slots.first.id;
  }

  Future<void> _loadSlot(SaveSlot slot) async {
    await _action(
      () => player.restore(widget.state.saves, widget.gameId, slot.id),
      'Loaded ${_slotLabel(slot).$1}',
    );
    await _closeMenu();
  }

  /// Load, reset, controls and screenshot live behind the Controls row, so
  /// the pause menu itself stays exactly the design's seven rows.
  Future<void> _controlsSheet(GameEntry game) async {
    final choice = await showOrbitOptionsSheet<String>(
      context,
      title: 'Controls',
      subtitle: 'This session',
      items: [
        OrbitSheetItem(
          label: padVisible
              ? 'Hide on-screen controls'
              : 'Show on-screen controls',
          icon: Symbols.sportsEsports,
          value: 'touch',
        ),
        OrbitSheetItem(
          label: 'Edit on-screen layout',
          icon: Symbols.tune,
          value: 'edit',
        ),
        OrbitSheetItem(
          label: fastForward ? 'Normal speed' : 'Fast-forward',
          icon: Symbols.fastForward,
          value: 'ff',
          enabled: _running,
        ),
        OrbitSheetItem(
          label: 'Restart game',
          icon: Symbols.restartAlt,
          value: 'restart',
          enabled: _running,
        ),
        OrbitSheetItem(
          label: 'Take screenshot',
          icon: Symbols.photoCamera,
          value: 'shot',
          enabled: player.frame != null,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'touch':
        setState(() => padVisible = !padVisible);
        await widget.state.setSetting('touchOverlay', padVisible);
      case 'edit':
        final size = MediaQuery.sizeOf(context);
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => LayoutEditorScreen(
              store: _layouts,
              system: game.system,
              portrait: size.height > size.width,
              coreId: game.coreId,
              frame: _frame,
            ),
          ),
        );
        padNavigationEnabled.value = true;
        if (mounted) setState(() {});
      case 'ff':
        setState(() => player.fastForward = !fastForward);
      case 'restart':
        await _restartGame(game);
      case 'shot':
        await _action(_screenshot);
    }
  }

  Future<void> _restartGame(GameEntry game) async {
    final ok = await showOrbitDialog<bool>(
      context,
      title: 'Restart ${game.title}?',
      body:
          'Starts from the title screen. A snapshot of this moment is kept in '
          'your time capsule first.',
      icon: Symbols.restartAlt,
      actions: const [
        OrbitDialogAction(label: 'Keep playing', value: false),
        OrbitDialogAction(
          label: 'Restart',
          value: true,
          kind: OrbitDialogActionKind.primary,
        ),
      ],
    );
    if (ok != true || !mounted) return;
    if (_running) await _action(_saveMoment);
    await _action(player.worker.reset);
    if (mounted) {
      orbitToast(context, 'Restarted · this moment kept as a snapshot');
    }
    await _closeMenu();
  }

  Future<void> _quitFlow(GameEntry game) async {
    final ok = await showOrbitDialog<bool>(
      context,
      title: 'Back to the library?',
      body:
          'ezCORE takes a snapshot of ${game.title} as you leave, so you’ll '
          'pick up exactly here next time.',
      icon: Symbols.logout,
      actions: const [
        OrbitDialogAction(label: 'Keep playing', value: false),
        OrbitDialogAction(
          label: 'Quit to library',
          value: true,
          kind: OrbitDialogActionKind.primary,
        ),
      ],
    );
    if (ok != true || !mounted) return;
    await _closeMenu(resume: false);
    await _exit();
  }
}

// ---------------------------------------------------------------------------
// Pause layer pieces
// ---------------------------------------------------------------------------

enum _PauseKind { panel, compact, sheet }

/// The design's three pause shapes: a 470 panel beside the receded picture,
/// a narrow landscape panel with a two-column menu, and a phone sheet.
class _PauseMetrics {
  const _PauseMetrics({
    required this.kind,
    required this.panelWidth,
    required this.sheetTop,
    required this.stripTop,
    required this.cardWidth,
    required this.cardHeight,
  });

  final _PauseKind kind;
  final double panelWidth;
  final double sheetTop;
  final double stripTop;
  final double cardWidth;
  final double cardHeight;

  static _PauseMetrics of(_PauseKind kind, Size size) => switch (kind) {
    _PauseKind.panel => _PauseMetrics(
      kind: kind,
      panelWidth: math.min(470, size.width * 0.5),
      sheetTop: 0,
      stripTop: size.height * 0.7133,
      cardWidth: 198,
      cardHeight: 112,
    ),
    _PauseKind.compact => _PauseMetrics(
      kind: kind,
      panelWidth: (size.width * 0.498).clamp(320.0, 520.0),
      sheetTop: 0,
      stripTop: size.height * 0.749,
      cardWidth: 103,
      cardHeight: 56,
    ),
    _PauseKind.sheet => _PauseMetrics(
      kind: kind,
      panelWidth: size.width,
      sheetTop: size.height * 0.409,
      stripTop: 0,
      cardWidth: 108,
      cardHeight: 59,
    ),
  };

  /// The phone sheet's picture: a 4:3 still above the sheet, not the game's
  /// own shape.
  Rect sheetFrame(Size stage) {
    final width = stage.width * 0.7256;
    final height = width * 207 / 283;
    return Rect.fromLTWH(
      (stage.width - width) / 2,
      stage.height * 0.0806,
      width,
      height,
    );
  }

  /// Where the picture goes while the menu is open, and how big.
  ({Offset center, double scale, double tilt}) recede(
    Rect base,
    Size stage,
    double t, {
    required bool reduce,
  }) {
    switch (kind) {
      case _PauseKind.panel:
        final scale = reduce ? 0.6 : 0.56;
        final center = Offset(stage.width * 0.7292, stage.height * 0.333);
        return (
          center: Offset.lerp(base.center, center, t)!,
          scale: 1 + (scale - 1) * t,
          tilt: reduce ? 0 : 8 * math.pi / 180 * t,
        );
      case _PauseKind.compact:
        final scale = math.min(
          0.68,
          (stage.width - panelWidth - 60) / base.width,
        );
        final w = base.width * scale;
        final target = Offset(stage.width - 44 - w / 2, stage.height * 0.410);
        return (
          center: Offset.lerp(base.center, target, t)!,
          scale: 1 + (scale - 1) * t,
          tilt: 0,
        );
      case _PauseKind.sheet:
        return (center: base.center, scale: 1, tilt: 0);
    }
  }

  /// The card's box once receded — the landscape strip lines up with it.
  Rect recededRect(Rect base, Size stage, {required bool reduce}) {
    final r = recede(base, stage, 1, reduce: reduce);
    return Rect.fromCenter(
      center: r.center,
      width: base.width * r.scale,
      height: base.height * r.scale,
    );
  }
}

class _MenuEntry {
  const _MenuEntry(
    this.id,
    this.icon,
    this.label,
    this.shortLabel, {
    this.hint,
    this.enabled = true,
  });

  final String id;
  final IconData icon;
  final String label;
  final String shortLabel;
  final String? hint;
  final bool enabled;
}

/// One pause row: 54 px on the wide panel, 46 on a phone.
class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.entry,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.shortLabel = false,
    this.height = 54,
    this.iconSize = 20,
    this.labelSize = 17,
    this.hintSize = 13,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 16, 0),
    this.showHint = true,
  });

  final _MenuEntry entry;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool shortLabel;
  final double height;
  final double iconSize;
  final double labelSize;
  final double hintSize;
  final EdgeInsets padding;
  final bool showHint;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final active = e.enabled && (_focus || _hover);
    final decoration = e.enabled && active
        ? BoxDecoration(
            color: const Color(0xFF2E3A4B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tokens.accent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Tokens.accent.withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Color(0x59007BFF),
                offset: Offset(0, 4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          )
        : BoxDecoration(
            color: e.enabled
                ? const Color(0xFF192433)
                : const Color(0xFF141D29),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: e.enabled
                  ? const Color(0xFF35404E)
                  : const Color(0x2235404E),
            ),
          );
    final foreground = e.enabled
        ? Tokens.text
        : Tokens.muted.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      enabled: e.enabled,
      label: e.label,
      child: FocusableActionDetector(
        enabled: e.enabled,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        mouseCursor: e.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onFocusChange: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (e.enabled) widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: e.enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            key: ValueKey('pause-row-${e.id}'),
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            height: widget.height,
            padding: widget.padding,
            decoration: decoration,
            child: Row(
              children: [
                Icon(e.icon, size: widget.iconSize, color: foreground, fill: 1),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.shortLabel ? e.shortLabel : e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: widget.labelSize,
                      weight: FontWeight.w500,
                      color: foreground,
                      height: null,
                    ),
                  ),
                ),
                if (e.hint != null && widget.showHint)
                  Text(
                    e.hint!,
                    style: Tokens.body(
                      size: widget.hintSize,
                      weight: FontWeight.w400,
                      color: const Color(0xFF98A1AF),
                      height: null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _eyebrowText = 'TAKE A BREATHER';

TextStyle _eyebrowStyle(double size) => Tokens.display(
  size: size,
  weight: FontWeight.w600,
  ls: 0.3 * size,
  color: Tokens.iconBlue,
);

class _PausePanel extends StatelessWidget {
  const _PausePanel({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.onAction,
    required this.resumeFocus,
  });

  final double width;
  final String title;
  final String subtitle;
  final List<_MenuEntry> entries;
  final ValueChanged<String> onAction;
  final FocusNode resumeFocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF017263A), Color(0xF50B1421)],
          stops: [0, 0.65],
        ),
        border: Border(right: BorderSide(color: Color(0xFF28323F))),
        boxShadow: [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(18, 0),
            blurRadius: 60,
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_eyebrowText, style: _eyebrowStyle(13)),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.display(
                      size: 34,
                      weight: FontWeight.w600,
                      ls: -0.02 * 34,
                      color: Colors.white,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 14,
                      color: Tokens.muted,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 29),
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) SizedBox(height: i == 1 ? 9 : 6),
                    _MenuButton(
                      entry: entries[i],
                      autofocus: i == 0,
                      focusNode: i == 0 ? resumeFocus : null,
                      onTap: () => onAction(entries[i].id),
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

/// Phone landscape: a narrower panel, a two-column menu, Quit apart.
class _PauseCompactPanel extends StatelessWidget {
  const _PauseCompactPanel({
    required this.width,
    required this.title,
    required this.entries,
    required this.onAction,
    required this.resumeFocus,
  });

  final double width;
  final String title;
  final List<_MenuEntry> entries;
  final ValueChanged<String> onAction;
  final FocusNode resumeFocus;

  @override
  Widget build(BuildContext context) {
    final grid = entries.where((e) => e.id != 'restart').toList();
    Widget cell(_MenuEntry e, {bool autofocus = false}) => _MenuButton(
      entry: e,
      autofocus: autofocus,
      focusNode: autofocus ? resumeFocus : null,
      shortLabel: true,
      height: 46,
      iconSize: 20,
      labelSize: 15,
      hintSize: 12,
      padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
      showHint: false,
      onTap: () => onAction(e.id),
    );
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(54, 22, 22, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF017263A), Color(0xF50B1421)],
          stops: [0, 0.65],
        ),
        border: Border(right: BorderSide(color: Color(0xFF28323F))),
        boxShadow: [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(18, 0),
            blurRadius: 60,
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_eyebrowText, style: _eyebrowStyle(11)),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.display(
                    size: 26,
                    weight: FontWeight.w600,
                    ls: -0.02 * 26,
                    color: Colors.white,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < grid.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: cell(grid[i], autofocus: i == 0)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: i + 1 < grid.length
                            ? cell(grid[i + 1])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone portrait: the pause menu becomes a sheet; the picture stays above.
class _PauseSheet extends StatelessWidget {
  const _PauseSheet({
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.onAction,
    required this.resumeFocus,
    required this.strip,
  });

  final String title;
  final String subtitle;
  final List<_MenuEntry> entries;
  final ValueChanged<String> onAction;
  final FocusNode resumeFocus;

  /// Heading plus snapshot cards, laid out by the stage (it owns the slots).
  final Widget strip;

  @override
  Widget build(BuildContext context) {
    final grid = entries.where((e) => e.id != 'restart').toList();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF217263A), Color(0xFA0A121E)],
          stops: [0, 0.7],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x2BDDE6F4))),
        boxShadow: [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, -18),
            blurRadius: 46,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Tokens.text.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(_eyebrowText, style: _eyebrowStyle(11)),
                const SizedBox(height: 9),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.display(
                    size: 29,
                    weight: FontWeight.w600,
                    ls: -0.02 * 29,
                    color: Colors.white,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(size: 12, color: Tokens.muted),
                ),
                const SizedBox(height: 7),
                for (var i = 0; i < grid.length; i += 3) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var k = 0; k < 3; k++) ...[
                        if (k > 0) const SizedBox(width: 12),
                        Expanded(
                          child: i + k < grid.length
                              ? _SheetAction(
                                  entry: grid[i + k],
                                  autofocus: i + k == 0,
                                  focusNode: i + k == 0 ? resumeFocus : null,
                                  onTap: () => onAction(grid[i + k].id),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 7),
                strip,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One big touch target in the phone sheet's grid.
class _SheetAction extends StatefulWidget {
  const _SheetAction({
    required this.entry,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  final _MenuEntry entry;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_SheetAction> createState() => _SheetActionState();
}

class _SheetActionState extends State<_SheetAction> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final active = e.enabled && (_focus || _hover);
    return Semantics(
      button: true,
      enabled: e.enabled,
      label: e.label,
      child: FocusableActionDetector(
        enabled: e.enabled,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        mouseCursor: e.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onFocusChange: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (e.enabled) widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: e.enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            key: ValueKey('pause-sheet-${e.id}'),
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            height: 74,
            decoration: active
                ? BoxDecoration(
                    color: const Color(0xFF2E3A4B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tokens.accent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Tokens.accent.withValues(alpha: 0.55),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: Color(0x59007BFF),
                        offset: Offset(0, 4),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  )
                : BoxDecoration(
                    color: e.enabled
                        ? const Color(0xFF192433)
                        : const Color(0xFF141D29),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: e.enabled
                          ? const Color(0xFF35404E)
                          : const Color(0x2235404E),
                    ),
                  ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  e.icon,
                  size: 18,
                  fill: 1,
                  color: e.enabled
                      ? Tokens.text
                      : Tokens.muted.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  e.shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: e.enabled
                        ? Tokens.text
                        : Tokens.muted.withValues(alpha: 0.5),
                    height: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How a snapshot card reads, per the design's three placements.
enum _SnapStyle {
  /// Wide strip: ring tag for autosave, label and time underneath.
  wide,

  /// Phone sheet: the whole label in a pill on the picture.
  sheet,

  /// Phone landscape: the label alone along the bottom of the picture.
  compact,
}

/// "Snapshots": the heading and the cards, in the design's three placements.
class _SnapshotStrip {
  const _SnapshotStrip({
    required this.slots,
    required this.style,
    required this.cardWidth,
    required this.cardHeight,
    required this.headingSize,
    required this.gap,
    required this.onLoad,
  });

  final List<SaveSlot> slots;
  final _SnapStyle style;
  final double cardWidth;
  final double cardHeight;
  final double headingSize;
  final double gap;
  final ValueChanged<SaveSlot> onLoad;

  Widget heading() => Text(
    'Snapshots',
    style: Tokens.display(
      size: headingSize,
      weight: FontWeight.w600,
      ls: 0,
      color: Colors.white,
      height: 1,
    ),
  );

  /// Heading over the cards, for the phone sheet.
  Widget block() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [heading(), const SizedBox(height: 23), cards()],
  );

  Widget cards() => SizedBox(
    height: cardHeight + (style == _SnapStyle.wide ? 32 : 0),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: slots.length,
      separatorBuilder: (_, _) => SizedBox(width: gap),
      itemBuilder: (context, i) => _SnapshotCard(
        slot: slots[i],
        width: cardWidth,
        height: cardHeight,
        style: style,
        onTap: () => onLoad(slots[i]),
      ),
    ),
  );
}

class _SnapshotCard extends StatefulWidget {
  const _SnapshotCard({
    required this.slot,
    required this.width,
    required this.height,
    required this.style,
    required this.onTap,
  });

  final SaveSlot slot;
  final double width;
  final double height;
  final _SnapStyle style;
  final VoidCallback onTap;

  @override
  State<_SnapshotCard> createState() => _SnapshotCardState();
}

class _SnapshotCardState extends State<_SnapshotCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final (label, tag, tagColor) = _slotLabel(widget.slot);
    // Wide strip: a ring tag for autosave/recovered, the label underneath.
    // Phone sheet: the whole label in a pill. Phone landscape: the label
    // alone along the bottom, as the device boards draw it.
    final pill = switch (widget.style) {
      _SnapStyle.wide => tag,
      _SnapStyle.sheet || _SnapStyle.compact => tag ?? label,
    };
    final when = _slotWhen(widget.slot);
    final active = _hover || _focus;
    final phone = widget.style != _SnapStyle.wide;
    return Semantics(
      button: true,
      label: '$label, $when',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onFocusChange: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
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
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: Tokens.fastDur,
                  curve: Tokens.ease,
                  width: widget.width,
                  height: widget.height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(phone ? 8 : 10),
                    boxShadow: active ? Tokens.halo : Tokens.ring,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(phone ? 8 : 10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF1F5564),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(phone ? 8 : 10),
                          ),
                          child: const CustomPaint(
                            painter: _SnapshotStripesPainter(),
                          ),
                        ),
                        if (pill != null)
                          Positioned(
                            left: 8,
                            top: phone ? null : 7,
                            bottom: phone ? 7 : null,
                            child: Container(
                              height: phone ? 21 : 23,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF05151F),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pill,
                                style: Tokens.body(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: tag != null ? tagColor : Colors.white,
                                  height: null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: widget.style == _SnapStyle.wide ? 9 : 0),
                if (widget.style == _SnapStyle.wide)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: Tokens.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: Tokens.text,
                            height: null,
                          ),
                        ),
                        TextSpan(
                          text: ' · $when',
                          style: Tokens.body(
                            size: 14,
                            weight: FontWeight.w400,
                            color: Tokens.muted,
                            height: null,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Autosave, the quick slot and recovered snapshots read as the design's
/// four cards; anything else is a numbered snapshot of its moment.
(String, String?, Color) _slotLabel(SaveSlot slot) {
  if (slot.id == _autoSlot) return ('Autosave', 'Auto', Tokens.systemLabelFg);
  if (slot.id == 'slot0') return ('Slot 1', null, Colors.white);
  if (slot.id == 'slot1') return ('Slot 2', null, Colors.white);
  if (slot.id.startsWith('crash')) {
    return ('Recovered', 'Crash-safe', Tokens.warn);
  }
  return ('Snapshot', null, Colors.white);
}

/// The design writes "Yesterday 21:30" rather than only the relative day,
/// and "Last week" for a recovered snapshot older than a week.
String _slotWhen(SaveSlot slot) {
  if (slot.id == _autoSlot) return 'when you stopped';
  final then = slot.modified;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(then.year, then.month, then.day);
  final days = today.difference(day).inDays;
  if (days == 1) {
    final hh = then.hour.toString().padLeft(2, '0');
    final mm = then.minute.toString().padLeft(2, '0');
    return 'Yesterday $hh:$mm';
  }
  if (days >= 7 && days < 14) return 'Last week';
  return lastPlayedLabel(slot.modified.millisecondsSinceEpoch);
}

/// The pause footer: what the keys do here, in the design's pill chips.
class _HintRow extends StatelessWidget {
  const _HintRow({required this.hints});
  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(width: 24),
            Container(
              constraints: const BoxConstraints(minWidth: 26),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF17242A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3E484E)),
              ),
              child: Text(
                hints[i].$1,
                style: Tokens.display(
                  size: 12,
                  weight: FontWeight.w600,
                  ls: 0,
                  color: Tokens.text,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              hints[i].$2,
              style: Tokens.body(
                size: 14,
                weight: FontWeight.w400,
                color: Tokens.muted,
                height: null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerHud extends StatelessWidget {
  const _PlayerHud({
    required this.glyph,
    required this.onTap,
    this.compact = false,
  });
  final String glyph;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('player-hud'),
      button: true,
      label: 'Menu',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 16 : 12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: compact ? 32 : 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2029),
                borderRadius: BorderRadius.circular(compact ? 16 : 12),
                border: Border.all(color: const Color(0xFF26343D)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (compact)
                    const _MenuGlyph()
                  else
                    Container(
                      constraints: const BoxConstraints(minWidth: 26),
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF232F39),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        glyph,
                        style: Tokens.display(
                          size: 13,
                          weight: FontWeight.w600,
                          ls: 0,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    'Menu',
                    style: Tokens.body(
                      size: compact ? 13 : 15,
                      weight: compact ? FontWeight.w600 : FontWeight.w500,
                      color: Colors.white,
                      height: null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three rounded bars, the design's menu mark on touch layouts.
class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 12,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: 2,
              decoration: BoxDecoration(
                color: Tokens.text,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// The striped still the design uses for snapshots and the pause sheet.
class _SnapshotStripesPainter extends CustomPainter {
  const _SnapshotStripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xFF003846));
    final stripe = Paint()..color = const Color(0xFF004957);
    const period = 21.0;
    for (var x = -size.height; x < size.width + size.height; x += period) {
      final band = Path()
        ..moveTo(x, 0)
        ..lineTo(x + period / 2, 0)
        ..lineTo(x + period / 2 - size.height, size.height)
        ..lineTo(x - size.height, size.height)
        ..close();
      canvas.drawPath(band, stripe);
    }
  }

  @override
  bool shouldRepaint(_SnapshotStripesPainter oldDelegate) => false;
}

/// Draws a frame into a box the way `BoxFit.cover` would: the picture keeps
/// its proportions and the overflow is cropped, never stretched.
class _CoverPicturePainter extends CustomPainter {
  _CoverPicturePainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = image.width.toDouble(), h = image.height.toDouble();
    final scale = math.max(size.width / w, size.height / h);
    final src = Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: size.width / scale,
      height: size.height / scale,
    );
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_CoverPicturePainter old) => old.image != image;
}

/// The launch notice: a 52 px pill that sits under the top edge, not the
/// bottom-anchored toast used elsewhere.
class _PlayerToast extends StatelessWidget {
  const _PlayerToast({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 21),
        decoration: BoxDecoration(
          color: const Color(0xFF101C24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A3944)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Symbols.bookmarkAdded,
              size: 18,
              color: Color(0xFF3B9CED),
              fill: 1,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.body(
                  size: 15,
                  weight: FontWeight.w500,
                  color: const Color(0xFFE8EEF2),
                  height: null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The blurred, saturated copy of the picture that lights the stage edges.
class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.image, this.opacity);
  final ui.Image image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.max(
      size.width / image.width,
      size.height / image.height,
    );
    final dst = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: image.width * scale,
      height: image.height * scale,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 70,
        sigmaY: 70,
        tileMode: TileMode.clamp,
      )
      ..colorFilter = ui.ColorFilter.matrix(_saturation(1.3, opacity));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint,
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.image != image || old.opacity != opacity;
}

/// A saturation matrix with an opacity multiplier in the alpha row.
List<double> _saturation(double s, double alpha) {
  const lumR = 0.2126;
  const lumG = 0.7152;
  const lumB = 0.0722;
  final inv = 1 - s;
  return [
    lumR * inv + s, lumG * inv, lumB * inv, 0, 0, //
    lumR * inv, lumG * inv + s, lumB * inv, 0, 0, //
    lumR * inv, lumG * inv, lumB * inv + s, 0, 0, //
    0, 0, 0, alpha, 0, //
  ];
}
