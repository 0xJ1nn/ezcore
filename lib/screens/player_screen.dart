import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../controls/layout_editor.dart';
import '../controls/retro_keys.dart';
import '../controls/layout_store.dart';
import '../controls/control_layout.dart';
import '../controls/control_overlay.dart';
import '../emu/player_controller.dart';
import '../emu/process_session_backend.dart';
import '../services/bios_check.dart';
import '../services/core_discovery.dart';
import '../services/cover_art.dart';
import '../services/gamepad.dart';
import '../services/pad_mapping.dart';
import '../widgets/pad_navigator.dart';
import '../services/core_staging.dart';
import '../services/repo_layout.dart';
import '../services/runtime_loader.dart';
import '../services/scoped_files.dart';
import '../services/local_data_dir.dart';

import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'cheats_screen.dart';

/// Orbit Player — video stage + dock control bar + "Take a breather"
/// session overlay (final-01). All emulation wiring preserved:
/// verified core launch, worker frames, PCM, pause, quick-save,
/// fast-forward, screenshot, touch pad, cheats, save/load, reset.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.gameId,
    required this.state,
    this.initialSlot,
  });
  final String gameId;
  final AppState state;

  /// Save slot to restore right after boot (Resume, or a chosen save).
  final String? initialSlot;

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

  /// On-screen controls. On by default where touch is the main input,
  /// off on desktop (keyboard and pads); the player can flip it any time.
  bool padVisible = true;
  final _overlayKey = GlobalKey<ControlOverlayState>();
  late final _layouts = LayoutStore(widget.state);
  bool _menuOpen = false;
  String? launchError;
  bool leaving = false;
  late final Future<void> opening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        widget.state.settings['touchOverlay'] as bool? ??
        (Platform.isAndroid || Platform.isIOS);
    opening = _launch();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get launching =>
      launchError == null &&
      player.error == null &&
      !player.running &&
      player.frame == null;

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
        // Per-game SRAM dir: cores name battery files freely (some use
        // fixed names), so a shared dir would corrupt saves across games.
        final saves = await Directory(
          '${data.path}/sram/${game.id}',
        ).create(recursive: true);
        if (!mounted || leaving) return;
        final runtimeRef = await resolveRuntimeRef();
        // Crash protection (P6, ADR-015): off by default. When on, the core
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
    } catch (e) {
      if (mounted) setState(() => launchError = 'Launch failed: $e');
    }
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
  }

  Future<void> _autoSave() async {
    if (!player.running || player.error != null || launchError != null) {
      return;
    }
    try {
      await player.save(widget.state.saves, widget.gameId, 'auto');
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
    final frame = player.frame;
    if (frame == null || !player.running) return;
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

  @override
  Widget build(BuildContext context) {
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    return PopScope(
      canPop: false,
      // Back (gesture or button) opens the pause menu; leaving the game is
      // a deliberate choice there, so a stray swipe never loses progress.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_openMenu());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => _stage(game.system, c.biggest),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage(String system, Size size) {
    final portrait = size.height > size.width;
    final layout = _layouts.resolve(
      system,
      portrait: portrait,
      coreId: widget.state.games
          .where((g) => g.id == widget.gameId)
          .firstOrNull
          ?.coreId,
    );
    final showControls = padVisible && player.running;
    final screen = showControls
        ? layout.screen
        : const ScreenSpec(rect: NormRect(0, 0, 1, 1));
    final box = screen.rect.resolve(size.width, size.height);
    final failed = launchError ?? player.error;
    final frame = player.frame;
    // Mouse always; touch only when the on-screen controls are hidden (the
    // overlay owns touch otherwise, and routes picture touches itself).
    void route(PointerEvent e) {
      if (e.kind == PointerDeviceKind.mouse || !showControls) {
        _onMouse(e, screen, size);
      }
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: route,
      onPointerMove: route,
      onPointerHover: route,
      onPointerUp: route,
      onPointerCancel: route,
      child: Stack(
        children: [
          if (showControls)
            Positioned.fill(
              child: CustomPaint(painter: ShellPainter(layout.shell)),
            ),
          if (frame != null && failed == null)
            Positioned.fill(
              child: CustomPaint(painter: GamePicturePainter(frame, screen)),
            ),
          if (failed != null || frame == null)
            Positioned.fromRect(
              rect: box,
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
                      ? const CircularProgressIndicator(color: Tokens.accent)
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
                layout: layout,
                onInput: (input, pressed) {
                  final id = retroPadId(input);
                  if (id != null) _action(() => player.button(id, pressed));
                },
                onHostInput: _hostInput,
                onTouch: _buzz,
                toFrame: (p, sz) => frame == null
                    ? null
                    : frameCoordinate(
                        screen,
                        sz,
                        frame.width / frame.height,
                        p,
                      ),
                onPicture: (at, pressed) {
                  final (x, y) = toPointer(at);
                  _action(() => player.pointer(x, y, pressed));
                },
              ),
            )
          else
            Positioned(
              top: 8,
              left: 8,
              child: OrbitIconButton(
                icon: Icons.menu,
                tooltip: 'Menu (Esc)',
                onPressed: _openMenu,
              ),
            ),
          if (fastForward || player.audioError != null)
            Positioned(
              top: 10,
              right: 12,
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
        ],
      ),
    );
  }

  /// The pause menu. Pauses the game while open, resumes it on close unless
  /// the player chose to leave.
  Future<void> _openMenu() async {
    if (_menuOpen || leaving) return;
    _menuOpen = true;
    padNavigationEnabled.value = true;
    _overlayKey.currentState?.releaseAll();
    // Pausing releases every button host-side, so the poller's emitted set
    // goes stale; forget it or a control still held on resume is never
    // re-sent.
    _gamepads.forgetHeld();
    final wasPaused = paused;
    if (player.running && !wasPaused) {
      await _action(() => player.setPaused(true));
    }
    if (!mounted) return;
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (context) => _PauseMenu(
        title: game.title,
        subtitle: systemLabels[game.system] ?? game.system,
        running: player.running,
        controlsShown: padVisible,
        fastForward: fastForward,
        hasFrame: player.frame != null,
      ),
    );
    _menuOpen = false;
    padNavigationEnabled.value =
        choice == 'quit' || choice == 'edit' || choice == 'cheats';
    if (!mounted) return;
    switch (choice) {
      case 'save':
        await _action(_saveMoment, 'State saved');
      case 'load':
        await _action(
          () => player.restore(widget.state.saves, widget.gameId, 'slot0'),
          'State loaded',
        );
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
        padNavigationEnabled.value = false;
      case 'edit':
        final size = MediaQuery.sizeOf(context);
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => LayoutEditorScreen(
              store: _layouts,
              system: game.system,
              portrait: size.height > size.width,
              coreId: game.coreId,
              frame: player.frame,
            ),
          ),
        );
        padNavigationEnabled.value = false;
        if (mounted) setState(() {});
      case 'controls':
        setState(() => padVisible = !padVisible);
        await widget.state.setSetting('touchOverlay', padVisible);
      case 'ff':
        setState(() => player.fastForward = !fastForward);
      case 'shot':
        await _action(_screenshot);
      case 'reset':
        await _action(player.worker.reset, 'Game reset');
      case 'quit':
        await _exit();
        return;
    }
    if (mounted && player.running && !wasPaused) {
      await _action(() => player.setPaused(false));
    }
  }
}

/// Resume first and largest; everything else one tap away; Quit apart.
class _PauseMenu extends StatelessWidget {
  const _PauseMenu({
    required this.title,
    required this.subtitle,
    required this.running,
    required this.controlsShown,
    required this.fastForward,
    required this.hasFrame,
  });

  final String title;
  final String subtitle;
  final bool running;
  final bool controlsShown;
  final bool fastForward;
  final bool hasFrame;

  @override
  Widget build(BuildContext context) {
    Widget item(
      String id,
      IconData icon,
      String label, {
      bool enabled = true,
    }) => OutlinedButton.icon(
      onPressed: enabled ? () => Navigator.of(context).pop(id) : null,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: Tokens.text,
        side: const BorderSide(color: Tokens.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Paused',
                        style: Tokens.display(
                          size: 20,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '$title · $subtitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(size: 12, color: Tokens.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OrbitPrimary(
                  label: 'Resume',
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop('resume'),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 3.6,
                  children: [
                    item(
                      'save',
                      Icons.save_outlined,
                      'Save state',
                      enabled: running,
                    ),
                    item('load', Icons.history, 'Load state', enabled: running),
                    item('cheats', Icons.bolt_outlined, 'Cheats'),
                    item(
                      'controls',
                      Icons.gamepad_outlined,
                      controlsShown ? 'Hide controls' : 'Show controls',
                    ),
                    item(
                      'ff',
                      Icons.fast_forward_outlined,
                      fastForward ? 'Normal speed' : 'Fast-forward',
                      enabled: running,
                    ),
                    item(
                      'shot',
                      Icons.photo_camera_outlined,
                      'Screenshot',
                      enabled: hasFrame,
                    ),
                    item('edit', Icons.tune, 'Edit controls'),
                    item(
                      'reset',
                      Icons.restart_alt,
                      'Reset game',
                      enabled: running,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('quit'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Tokens.danger,
                  ),
                  child: const Text('Quit to library'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
