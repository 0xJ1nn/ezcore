import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../emu/player_controller.dart';
import '../services/bios_check.dart';
import '../services/core_discovery.dart';
import '../services/gamepad.dart';
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
import 'settings_screen.dart';

/// Orbit Player — video stage + dock control bar + "Take a breather"
/// session overlay (final-01). All emulation wiring preserved:
/// verified core launch, worker frames, PCM, pause, quick-save,
/// fast-forward, screenshot, touch pad, cheats, save/load, reset.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen(
      {super.key, required this.gameId, required this.state, this.initialSlot});
  final String gameId;
  final AppState state;

  /// Save slot to restore right after boot (Time capsule resume).
  final String? initialSlot;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  final player = PlayerController();
  final _scoped = createScopedFiles();
  final _gamepads = GamepadService();
  VoidCallback? _cancelPad;

  /// Staged vault cores (populated at startup by [CoreStagingService]).
  static String? _vaultCoresRoot() {
    final vault = CoreStagingService.vaultDir();
    return vault.existsSync() ? vault.path : null;
  }

  /// Release-bundle cores — the read-only fallback when staging hasn't run
  /// (or the vault was cleared): macOS `<app>/Contents/Resources/ezcore/cores`.
  static String? _bundledCoresRoot() {
    final roots = RepoLayout.bundledCoreRoots(
        executablePath: Platform.resolvedExecutable);
    return roots.isEmpty ? null : roots.first;
  }
  bool get paused => player.paused;
  bool get fastForward => player.fastForward;
  bool padVisible = true;
  String? launchError;
  bool leaving = false;
  late final Future<void> opening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    player.addListener(_refresh);
    _cancelPad = _gamepads.onButton((event) {
      final id = event.retroPadId;
      if (id != null) _action(() => player.button(id, event.pressed));
    });
    padVisible =
        widget.state.settings['touchOverlay'] as bool? ?? true;
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
      final root = widget.state.settings['coreDirectory'] as String? ??
          Platform.environment['EZCORE_CORES_DIR'] ??
          _vaultCoresRoot() ??
          _bundledCoresRoot() ??
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
        await player.open(
          runtimeRef: runtimeRef,
          corePath: corePath,
          contentPath: File(game.filePath).absolute.path,
          systemDir: system.path,
          saveDir: saves.path,
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

  /// Pushes stored cheats into the live session. Silent unless the core
  /// rejects an index or the call itself fails.
  Future<void> _applyCheats() async {
    if (!mounted || leaving || !player.running) return;
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    final cheats = widget.state.cheatsFor(game.id);
    if (cheats.isEmpty) return;
    try {
      final rejected = await player.applyCheats(cheats);
      if (rejected.isNotEmpty && mounted) {
        orbitToast(context,
            '${rejected.length} cheat(s) rejected by this core');
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
      unawaited(_action(() => player.setPaused(true)));
      if (widget.state.settings['autosave'] != false) {
        unawaited(_autoSave());
      }
    }
  }

  @override
  void dispose() {
    leaving = true;
    _cancelPad?.call();
    _gamepads.dispose();
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
        final game =
            widget.state.games.firstWhere((g) => g.id == widget.gameId);
        final art = File('${data.path}/art/${game.id}.png');
        await art.parent.create(recursive: true);
        await file.copy(art.path);
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
    await player.save(
        widget.state.saves, widget.gameId, 'slot-$stamp');
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

  Widget _touch(String label, int id) => Listener(
        onPointerDown: (_) {
          _buzz();
          _action(() => player.button(id, true));
        },
        onPointerUp: (_) => _action(() => player.button(id, false)),
        onPointerCancel: (_) => _action(() => player.button(id, false)),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x0ADDE6F4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x26DDE6F4)),
          ),
          child: Text(label, style: Tokens.body(size: 12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    final sysLabel = systemLabels[game.system] ?? game.system;
    return Scaffold(
      backgroundColor: Tokens.bg,
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: _exit,
        ),
        title: Text('$sysLabel · ${game.coreId}',
            style: Tokens.body(size: 12, color: Tokens.muted)),
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          final keys = {
            LogicalKeyboardKey.arrowUp: 4,
            LogicalKeyboardKey.arrowDown: 5,
            LogicalKeyboardKey.arrowLeft: 6,
            LogicalKeyboardKey.arrowRight: 7,
            LogicalKeyboardKey.keyZ: 0,
            LogicalKeyboardKey.keyX: 8,
            LogicalKeyboardKey.enter: 3,
            LogicalKeyboardKey.shiftRight: 2,
          };
          final id = keys[event.logicalKey];
          if (id == null) return KeyEventResult.ignored;
          _action(() => player.button(id, event is! KeyUpEvent));
          return KeyEventResult.handled;
        },
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  border: Border.all(color: const Color(0x22DDE6F4)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 14),
                        blurRadius: 34),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg - 1),
                  child: launchError != null || player.error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              launchError ?? player.error!,
                              style: Tokens.body(
                                  size: 12, color: Tokens.danger)),
                        )
                      : player.frame != null
                          ? RawImage(
                              image: player.frame,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none,
                            )
                          : launching
                              ? const CircularProgressIndicator(
                                  color: Tokens.accent)
                              : Text('Waiting for video…',
                                  style: Tokens.body(
                                      size: 12, color: Tokens.muted)),
                ),
              ),
            ),
            if (player.audioError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(player.audioError!,
                    maxLines: 2,
                    style: Tokens.body(size: 11, color: Tokens.danger)),
              ),
            if (paused)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Paused — take a breather',
                    style: Tokens.body(size: 11, color: Tokens.muted)),
              ),
            if (padVisible && player.running)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _touch('↑', 4),
                    _touch('↓', 5),
                    _touch('←', 6),
                    _touch('→', 7),
                    _touch('B', 0),
                    _touch('A', 8),
                    _touch('Select', 2),
                    _touch('Start', 3),
                  ],
                ),
              ),
            _dock(),
          ],
        ),
      ),
    );
  }

  Widget _dock() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: Tokens.dockDecor,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _DockBtn(
              icon: paused ? Icons.play_arrow : Icons.pause,
              label: paused ? 'Resume' : 'Pause',
              enabled: player.running,
              onTap: player.running
                  ? () async {
                      if (paused) {
                        await _action(() => player.setPaused(false));
                      } else {
                        await _action(() => player.setPaused(true));
                        if (mounted) _session();
                      }
                    }
                  : null,
            ),
            _DockBtn(
              icon: Icons.save_outlined,
              label: 'Save',
              enabled: player.running,
              onTap: player.running
                  ? () => _action(
                      _saveMoment,
                      'Moment saved to your time capsule',
                    )
                  : null,
            ),
            _DockBtn(
              icon: Icons.fast_forward_outlined,
              label: 'FF',
              active: fastForward,
              onTap: () {
                setState(() => player.fastForward = !fastForward);
                orbitToast(
                    context,
                    fastForward
                        ? 'Fast-forward on'
                        : 'Fast-forward off');
              },
            ),
            _DockBtn(
              icon: Icons.photo_camera_outlined,
              label: 'Shot',
              enabled: player.frame != null,
              onTap: player.frame != null
                  ? () => _action(_screenshot)
                  : null,
            ),
            _DockBtn(
              icon: Icons.gamepad_outlined,
              label: 'Pad',
              active: padVisible,
              onTap: () =>
                  setState(() => padVisible = !padVisible),
            ),
            _DockBtn(
              icon: Icons.bolt_outlined,
              label: 'Cheats',
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CheatsScreen(
                      gameId: widget.gameId,
                      state: widget.state,
                      onCheatsChanged: _applyCheats,
                    ),
                  ),
                );
                await _refreshStateCount();
              },
            ),
            _DockBtn(
              icon: Icons.more_horiz,
              label: 'More',
              onTap: _more,
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// "Take a breather" session overlay — final-01 §F.
  void _session() {
    final game =
        widget.state.games.firstWhere((g) => g.id == widget.gameId);
    final sysLabel = systemLabels[game.system] ?? game.system;
    showOrbitDialog(
      context,
      Padding(
        padding: const EdgeInsets.all(36),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GameCover(
                      gameId: game.id,
                      title: game.title,
                      system: sysLabel,
                      width: 56,
                      height: 78),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$sysLabel · ${game.coreId}',
                            style: Tokens.eyebrow),
                        const SizedBox(height: 4),
                        Text(game.title,
                            style: Tokens.display(
                                size: 16,
                                weight: FontWeight.w500,
                                ls: -0.4),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  OrbitRoundButton(
                    icon: Icons.close,
                    tooltip: 'Close session preview',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('IN-GAME OVERLAY', style: Tokens.eyebrow),
              const SizedBox(height: 8),
              Text('Take a breather.',
                  style: Tokens.display(
                      size: 32, weight: FontWeight.w500, ls: -0.7)),
              const SizedBox(height: 8),
              Text(
                'Your game stays within reach. Saves pin to your time capsule on this device.',
                style:
                    Tokens.body(size: 12, color: Tokens.muted, height: 1.7),
              ),
              const SizedBox(height: 16),
              OrbitPrimary(
                label: 'Return to game',
                expanded: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _action(() => player.setPaused(false));
                },
              ),
              const SizedBox(height: 12),
              _SessionRow(
                icon: Icons.save_outlined,
                label: 'Save a moment',
                tag: 'TIME CAPSULE',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _action(_saveMoment,
                      'Moment saved to your time capsule');
                  await _action(() => player.setPaused(false));
                },
              ),
              _SessionRow(
                icon: Icons.history_outlined,
                label: 'Open time capsule',
                tag: 'SNAPSHOTS',
                onTap: () {
                  Navigator.of(context).pop();
                  orbitToast(context,
                      'Snapshots live in the Capsule tab — exit to browse');
                },
              ),
              _SessionRow(
                icon: Icons.sports_esports_outlined,
                label: 'Controller settings',
                tag: 'CONFIGURE',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        state: widget.state,
                        initialTab: 'Controllers',
                      ),
                    ),
                  );
                },
              ),
              _SessionRow(
                icon: Icons.exit_to_app,
                label: 'Close game',
                tag: '',
                onTap: () {
                  Navigator.of(context).pop();
                  _exit();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _more() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.save, color: Tokens.text),
              title: Text('Save state — slot 0',
                  style: Tokens.body()),
              onTap: () {
                Navigator.of(context).pop();
                _action(
                  () => player.save(
                      widget.state.saves, widget.gameId, 'slot0'),
                  'Saved to slot 0',
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.upload, color: Tokens.text),
              title: Text('Load state — slot 0',
                  style: Tokens.body()),
              onTap: () {
                Navigator.of(context).pop();
                _action(
                  () => player.restore(
                    widget.state.saves,
                    widget.gameId,
                    'slot0',
                  ),
                  'State loaded',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt,
                  color: Tokens.text),
              title:
                  Text('Reset', style: Tokens.body()),
              onTap: () {
                Navigator.of(context).pop();
                _action(player.worker.reset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close,
                  color: Tokens.text),
              title: Text('Close game',
                  style: Tokens.body()),
              onTap: () {
                Navigator.of(context).pop();
                _exit();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DockBtn extends StatelessWidget {
  const _DockBtn({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.active = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Tokens.muted.withValues(alpha: 0.4)
        : active
            ? Tokens.accent
            : Tokens.text;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: Tokens.body(size: 8, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(
      {required this.icon,
      required this.label,
      required this.tag,
      required this.onTap});
  final IconData icon;
  final String label;
  final String tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Tokens.line),
        color: Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(icon, color: Tokens.text),
        title: Text(label, style: Tokens.body(size: 13)),
        trailing: tag.isEmpty
            ? null
            : Text(tag,
                style: Tokens.body(
                    size: 9, ls: 1.0, color: Tokens.muted)),
        onTap: onTap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}
