import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/core_manifest.dart';
import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../state/save_sync.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/system_hues.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_cover.dart';
import '../widgets/orbit_dialog.dart';
import '../widgets/orbit_sheet.dart';
import 'cheats_screen.dart';
import 'launch.dart';

/// One game's page — Orbit handoff §8.2.
///
/// The screen paints only its own content: the room tint, the angled cover,
/// the information column, the actions and the snapshots. The OS bar, rail,
/// backdrop and hint row belong to the shell.
///
/// One layout adapts to the space it has:
/// - desktop (≥ 1360): the 1440 × 900 composition — cover at 150/150 and the
///   right column at 600/120, with the breadcrumb above the title;
/// - tablet / narrow desktop (1180–1360): the 82 % composition, with the
///   breadcrumb above the cover, the cover giving the left third, and the
///   Enter chip, snapshot names and hint note dropped;
/// - tablet portrait and phone landscape: a stacked column;
/// - phone portrait: the 3a stack with ×0.85 type, a full-width Resume and a
///   horizontally scrolling snapshot row.
class GameDetailScreen extends StatefulWidget {
  const GameDetailScreen({
    super.key,
    required this.gameId,
    required this.state,
  });
  final String gameId;
  final AppState state;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  late Future<List<SaveSlot>> _saves = _load();

  AppState get state => widget.state;

  Future<List<SaveSlot>> _load() async {
    try {
      final slots = await state.saves.list(widget.gameId);
      return slots..sort((a, b) => b.modified.compareTo(a.modified));
    } catch (_) {
      return const [];
    }
  }

  void _reload() => setState(() {
    _saves = _load();
  });

  Future<void> _play(GameEntry g, {bool resume = false, String? slot}) async {
    await launchGame(context, state, g, resume: resume, slot: slot);
    if (mounted) _reload();
  }

  void _back() => Navigator.of(context).maybePop();

  Future<void> _gameMenu(GameEntry g, List<CoreManifest> cores) async {
    final choice = await showOrbitOptionsSheet<String>(
      context,
      title: g.title,
      subtitle: '${systemLabel(g.system)} · ${fileSizeLabel(g.fileSize)}',
      items: [
        OrbitSheetItem(
          label: g.favorite ? 'Remove from favourites' : 'Add to favourites',
          icon: Symbols.favorite,
          value: 'favourite',
        ),
        if (cores.length > 1)
          const OrbitSheetItem(
            label: 'Change core',
            icon: Symbols.memory,
            value: 'core',
          ),
        const OrbitSheetItem(
          label: 'Cheats',
          icon: Symbols.bolt,
          value: 'cheats',
        ),
        const OrbitSheetItem(
          label: 'Remove from library',
          icon: Symbols.delete,
          value: 'remove',
          danger: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'favourite':
        state.toggleFavorite(g.id);
      case 'core':
        await _chooseCore(g, cores);
      case 'cheats':
        await _openCheats(g);
      case 'remove':
        await _remove(g);
    }
  }

  Future<void> _chooseCore(GameEntry g, List<CoreManifest> cores) async {
    if (cores.isEmpty) return;
    final current = _coreFor(g, cores)?.id;
    final choice = await showOrbitOptionsSheet<String>(
      context,
      title: 'Core',
      subtitle: 'Choose which core plays this game. ezCORE remembers it.',
      items: [
        for (final m in cores)
          OrbitSheetItem(
            label: '${m.name} · ${m.version}',
            icon: Symbols.memory,
            value: m.id,
          ),
      ],
    );
    if (!mounted || choice == null || choice == current) return;
    state.setCore(g.id, choice);
  }

  Future<void> _openCheats(GameEntry g) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheatsScreen(gameId: g.id, state: state),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _snapshotMenu(SaveSlot slot) async {
    final choice = await showOrbitOptionsSheet<String>(
      context,
      title: saveName(slot.id),
      subtitle: snapshotWhen(slot),
      items: [
        const OrbitSheetItem(
          label: 'Load snapshot',
          icon: Symbols.playArrow,
          value: 'load',
        ),
        const OrbitSheetItem(
          label: 'Delete snapshot',
          icon: Symbols.delete,
          value: 'delete',
          danger: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final game = state.games.where((g) => g.id == widget.gameId).firstOrNull;
    if (game == null) return;
    switch (choice) {
      case 'load':
        await _play(game, slot: slot.id);
      case 'delete':
        await _deleteSave(slot);
    }
  }

  Future<void> _deleteSave(SaveSlot slot) async {
    final ok = await showOrbitConfirmDialog(
      context,
      title: 'Delete this snapshot?',
      body:
          '${saveName(slot.id)} from ${snapshotWhen(slot)}. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep',
    );
    if (!ok || !mounted) return;
    await state.saves.remove(widget.gameId, slot.id);
    final left = await _load();
    state.setStateCount(widget.gameId, left.length);
    if (mounted) {
      setState(() {
        _saves = Future.value(left);
      });
    }
  }

  Future<void> _remove(GameEntry g) async {
    final ok = await showOrbitConfirmDialog(
      context,
      title: 'Remove ${g.title}?',
      body:
          'It leaves your library. The game file on your device is not '
          'deleted, and you can add it again any time.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
    state.removeGame(g.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final game = state.games
            .where((g) => g.id == widget.gameId)
            .firstOrNull;
        if (game == null) return const Scaffold(backgroundColor: Tokens.bg);
        final media = MediaQuery.of(context);
        final layout = Layout.ofSize(media.size, media.orientation);
        return Scaffold(
          backgroundColor: Tokens.bg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _RoomTint(system: game.system),
              LayoutBuilder(
                builder: (context, c) {
                  return FutureBuilder<List<SaveSlot>>(
                    future: _saves,
                    builder: (context, snap) {
                      final saves = snap.data ?? const <SaveSlot>[];
                      final cores = state.registry.compatibleCores(
                        game.extension,
                      );
                      final cheatsOn = state
                          .cheatsFor(game.id)
                          .where((c) => c.enabled)
                          .length;
                      final data = _DetailData(
                        game: game,
                        saves: saves,
                        cheatsOn: cheatsOn,
                        core: _coreFor(game, cores),
                        canChangeCore: cores.length > 1,
                        actions: _DetailActions(
                          back: _back,
                          play: (resume) => _play(game, resume: resume),
                          playSlot: (id) => _play(game, slot: id),
                          cheats: () => _openCheats(game),
                          favourite: () => state.toggleFavorite(game.id),
                          core: cores.length > 1
                              ? () => _chooseCore(game, cores)
                              : null,
                          snapshotMenu: _snapshotMenu,
                        ),
                      );
                      final content = _content(
                        data,
                        layout,
                        c.maxWidth,
                        c.maxHeight,
                        media.padding,
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onLongPress: () => _gameMenu(game, cores),
                        onSecondaryTap: () => _gameMenu(game, cores),
                        child: content,
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _content(
    _DetailData data,
    OrbitLayout layout,
    double width,
    double height,
    EdgeInsets padding,
  ) {
    switch (layout) {
      case OrbitLayout.phonePortrait:
        return _PhonePortrait(
          data: data,
          width: width,
          topInset: padding.top,
          bottomInset: padding.bottom,
        );
      case OrbitLayout.phoneLandscape:
        return _LandscapeStack(data: data);
      case OrbitLayout.tabletPortrait:
        return _PortraitStack(data: data, width: width);
      case OrbitLayout.tablet:
      case OrbitLayout.desktop:
        return _WideDetail(data: data, width: width, height: height);
    }
  }

  CoreManifest? _coreFor(GameEntry game, List<CoreManifest> cores) {
    final byId = state.registry.catalog
        .where((m) => m.id == game.coreId)
        .firstOrNull;
    if (byId != null) return byId;
    return cores.isEmpty ? null : cores.first;
  }
}

// ---------------------------------------------------------------------------
// Data + actions shared by every family
// ---------------------------------------------------------------------------

class _DetailActions {
  const _DetailActions({
    required this.back,
    required this.play,
    required this.playSlot,
    required this.cheats,
    required this.favourite,
    required this.core,
    required this.snapshotMenu,
  });

  final VoidCallback back;
  final ValueChanged<bool> play;
  final ValueChanged<String> playSlot;
  final VoidCallback cheats;
  final VoidCallback favourite;
  final VoidCallback? core;
  final ValueChanged<SaveSlot> snapshotMenu;
}

class _DetailData {
  const _DetailData({
    required this.game,
    required this.saves,
    required this.cheatsOn,
    required this.core,
    required this.canChangeCore,
    required this.actions,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final int cheatsOn;
  final CoreManifest? core;
  final bool canChangeCore;
  final _DetailActions actions;

  bool get hasAuto => saves.any((s) => s.id == autoSlot);

  String get systemUpper => systemLabel(game.system).toUpperCase();

  String get primaryLabel => hasAuto ? 'Resume' : 'Play';

  String get coreName => core?.name ?? 'No core';

  String cheatsLabel({required bool full}) {
    if (cheatsOn <= 0) return 'Cheats';
    return full ? 'Cheats · $cheatsOn on' : 'Cheats · $cheatsOn';
  }

  String get metaLine {
    final last = game.lastPlayedMs > 0
        ? 'last ${lastPlayedLabel(game.lastPlayedMs).toLowerCase()}'
        : 'not played yet';
    return last;
  }
}

// ---------------------------------------------------------------------------
// Wide composition (desktop and tablet landscape)
// ---------------------------------------------------------------------------

class _WideDetail extends StatelessWidget {
  const _WideDetail({
    required this.data,
    required this.width,
    required this.height,
  });

  final _DetailData data;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // The design is drawn at 1440 × 900. At 1180 it becomes the 82 %
    // composition from Devices 5c; everything in between is interpolated.
    final t = ((width - 1180) / 260).clamp(0.0, 1.0);
    final desktop = width >= 1360;
    final coverLeft = _lerp(78, 150, t);
    final coverTop = _lerp(112, 150, t);
    final coverWidth = _lerp(300, 360, t);
    final rightX = coverLeft + coverWidth + _lerp(85, 88, t);
    final rightTop = _lerp(111, 118, t);
    final rightMargin = _lerp(60, 80, t);
    final rightWidth = math.max(320.0, width - rightX - rightMargin);
    final titleSize = _lerp(62, 76, t);
    final designHeight = math.max(height, 780.0);
    final compact = !desktop;

    return SingleChildScrollView(
      child: SizedBox(
        height: designHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: coverLeft,
              top: coverTop,
              child: _CoverArt(
                game: data.game,
                width: coverWidth,
                yaw: 14,
                pitch: 3,
                interactive: true,
              ),
            ),
            Positioned(
              left: rightX,
              top: rightTop,
              right: rightMargin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (desktop) ...[
                    _Breadcrumb(
                      title: data.game.title,
                      onBack: data.actions.back,
                    ),
                    SizedBox(height: desktop ? 34 : 33),
                  ],
                  _Badges(
                    game: data.game,
                    mode: desktop ? _BadgeMode.full : _BadgeMode.tablet,
                  ),
                  SizedBox(height: desktop ? 17 : 16),
                  _Title(
                    text: data.game.title,
                    size: titleSize,
                    align: TextAlign.start,
                    maxLines: 1,
                  ),
                  SizedBox(height: desktop ? 22 : 18),
                  _StatsStrip(data: data, compact: compact),
                  SizedBox(height: desktop ? 26 : 24),
                  _ActionRow(
                    data: data,
                    desktop: desktop,
                    t: t,
                    scale: compact ? 0.92 : 1,
                  ),
                  SizedBox(height: desktop ? 42 : 30),
                  _SnapshotHeader(showNote: desktop, phone: false),
                  const SizedBox(height: 14),
                  _SnapshotRow(
                    system: data.game.system,
                    saves: data.saves,
                    width: rightWidth,
                    cardWidth: 178,
                    thumbHeight: 110,
                    showNames: desktop,
                    showSlotTags: compact,
                    compactCaptions: compact,
                    onLoad: data.actions.playSlot,
                    onMenu: data.actions.snapshotMenu,
                  ),
                ],
              ),
            ),
            if (!desktop)
              Positioned(
                left: _lerp(22, 28, t),
                top: _lerp(26, 32, t),
                child: _Breadcrumb(
                  title: data.game.title,
                  onBack: data.actions.back,
                  libraryOnly: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stacked composition (tablet portrait, small landscape windows)
// ---------------------------------------------------------------------------

class _PortraitStack extends StatelessWidget {
  const _PortraitStack({required this.data, required this.width});
  final _DetailData data;
  final double width;

  @override
  Widget build(BuildContext context) {
    final side = 44.0;
    final coverWidth = math.min(280.0, width * 0.42);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(side, 24, side, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _RoundButton(
                  tooltip: 'Back',
                  icon: Symbols.arrowBack,
                  onPressed: data.actions.back,
                ),
                const Spacer(),
                _FavouriteButton(
                  favorite: data.game.favorite,
                  onPressed: data.actions.favourite,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: _CoverArt(
                game: data.game,
                width: coverWidth,
                yaw: 8,
                pitch: 2,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: _Badges(game: data.game, mode: _BadgeMode.tablet),
            ),
            const SizedBox(height: 18),
            Center(
              child: _Title(
                text: data.game.title,
                size: 44,
                align: TextAlign.center,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 10),
            Center(child: _MetaLine(text: data.metaLine)),
            const SizedBox(height: 26),
            Center(child: _StatsStrip(data: data, compact: true)),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: _actionChildren(
                data,
                compact: true,
                compactWidths: false,
              ),
            ),
            const SizedBox(height: 34),
            _SnapshotHeader(showNote: false, phone: false),
            const SizedBox(height: 14),
            _SnapshotRow(
              system: data.game.system,
              saves: data.saves,
              width: width - side * 2,
              cardWidth: 178,
              thumbHeight: 110,
              showNames: false,
              showSlotTags: true,
              compactCaptions: true,
              onLoad: data.actions.playSlot,
              onMenu: data.actions.snapshotMenu,
            ),
          ],
        ),
      ),
    );
  }
}

class _LandscapeStack extends StatelessWidget {
  const _LandscapeStack({required this.data});
  final _DetailData data;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          final pad = 20.0;
          final coverWidth = math.min(150.0, c.maxHeight * 0.36);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverArt(game: data.game, width: coverWidth, yaw: 8, pitch: 2),
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _RoundButton(
                            tooltip: 'Back',
                            icon: Symbols.arrowBack,
                            size: 36,
                            onPressed: data.actions.back,
                          ),
                          const Spacer(),
                          _FavouriteButton(
                            favorite: data.game.favorite,
                            onPressed: data.actions.favourite,
                            size: 36,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _Badges(game: data.game, mode: _BadgeMode.tablet),
                      const SizedBox(height: 10),
                      _Title(
                        text: data.game.title,
                        size: 30,
                        align: TextAlign.start,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      _MetaLine(text: data.metaLine),
                      const SizedBox(height: 12),
                      _StatsStrip(data: data, compact: true, dense: true),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _actionChildren(
                          data,
                          compact: true,
                          compactWidths: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SnapshotHeader(showNote: false, phone: true),
                      const SizedBox(height: 6),
                      _SnapshotRow(
                        system: data.game.system,
                        saves: data.saves,
                        width: c.maxWidth - pad * 2 - coverWidth - 26,
                        cardWidth: 116,
                        thumbHeight: 64,
                        showNames: false,
                        showSlotTags: true,
                        compactCaptions: true,
                        onLoad: data.actions.playSlot,
                        onMenu: data.actions.snapshotMenu,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<Widget> _actionChildren(
  _DetailData data, {
  required bool compact,
  required bool compactWidths,
}) {
  return [
    _ActionButton(
      label: data.primaryLabel,
      icon: Symbols.playArrow,
      primary: true,
      width: compactWidths ? 168 : null,
      height: compactWidths ? 44 : 52,
      fontSize: compactWidths ? 14 : 15,
      onPressed: () => data.actions.play(data.hasAuto),
    ),
    if (data.hasAuto)
      _ActionButton(
        label: 'From start',
        icon: Symbols.restartAlt,
        width: compactWidths ? 148 : null,
        height: compactWidths ? 44 : 52,
        fontSize: compactWidths ? 14 : 15,
        onPressed: () => data.actions.play(false),
      ),
    _ActionButton(
      label: data.cheatsLabel(full: false),
      icon: Symbols.bolt,
      width: compactWidths ? 138 : null,
      height: compactWidths ? 44 : 52,
      fontSize: compactWidths ? 14 : 15,
      onPressed: data.actions.cheats,
    ),
    SizedBox(
      width: compactWidths ? 44 : 52,
      height: compactWidths ? 44 : 52,
      child: _FavouriteButton(
        favorite: data.game.favorite,
        onPressed: data.actions.favourite,
        size: compactWidths ? 44 : 52,
      ),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Phone portrait (3a)
// ---------------------------------------------------------------------------

class _PhonePortrait extends StatelessWidget {
  const _PhonePortrait({
    required this.data,
    required this.width,
    required this.topInset,
    required this.bottomInset,
  });

  final _DetailData data;
  final double width;
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final side = 20.0;
    final coverWidth = 156.0;
    final coverHeight = coverWidth * 4 / 3;
    // The device render carries its own status bar; below it the page starts
    // 18 px in. With no padding (the capture surface) the design's 62 px
    // offset is the one to hit.
    final top = math.max(topInset + 18, 62.0);

    return SingleChildScrollView(
      padding: EdgeInsets.only(top: top, bottom: bottomInset + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40 + coverHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 40,
                  child: _CoverArt(
                    game: data.game,
                    width: coverWidth,
                    yaw: 6,
                    pitch: 1.5,
                    shadow: false,
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 0,
                  child: Row(
                    children: [
                      _RoundButton(
                        tooltip: 'Back',
                        icon: Symbols.arrowBack,
                        onPressed: data.actions.back,
                      ),
                      const Spacer(),
                      _FavouriteButton(
                        favorite: data.game.favorite,
                        onPressed: data.actions.favourite,
                        tone: _HeartTone.accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: _Badges(game: data.game, mode: _BadgeMode.phone),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Center(
              child: _Title(
                text: data.game.title,
                size: 36,
                align: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ),
          const SizedBox(height: 11),
          Center(child: _MetaLine(text: data.metaLine)),
          const SizedBox(height: 28),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActionButton(
                  label: data.primaryLabel,
                  icon: Symbols.playArrow,
                  primary: true,
                  height: 56,
                  fontSize: 16,
                  onPressed: () => data.actions.play(data.hasAuto),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (data.hasAuto) ...[
                      Expanded(
                        child: _ActionButton(
                          label: 'From start',
                          icon: Symbols.restartAlt,
                          height: 56,
                          fontSize: 16,
                          onPressed: () => data.actions.play(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: _ActionButton(
                        label: data.cheatsLabel(full: false),
                        icon: Symbols.bolt,
                        height: 56,
                        fontSize: 16,
                        onPressed: data.actions.cheats,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: _SnapshotHeader(showNote: false, phone: true),
          ),
          const SizedBox(height: 11),
          Padding(
            padding: EdgeInsets.only(left: side),
            child: _SnapshotRow(
              system: data.game.system,
              saves: data.saves,
              width: width - side,
              cardWidth: 148,
              thumbHeight: 90,
              showNames: false,
              showSlotTags: true,
              compactCaptions: true,
              onLoad: data.actions.playSlot,
              onMenu: data.actions.snapshotMenu,
              phone: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared parts
// ---------------------------------------------------------------------------

class _RoomTint extends StatelessWidget {
  const _RoomTint({required this.system});
  final String system;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RoomTintPainter(SystemHues.roomTintFor(system)),
        size: Size.infinite,
      ),
    );
  }
}

/// The room tint: a 70 % × 70 % ellipse at 22 % / 40 % in the game's
/// system hue, at 32 % (handoff §8.2). A circular [RadialGradient] uses the
/// shortest side, which would fade out down the tall phone; scaling the
/// canvas keeps the design's elliptical falloff.
class _RoomTintPainter extends CustomPainter {
  const _RoomTintPainter(this.tint);
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final shader = RadialGradient(
      colors: [tint.withValues(alpha: 0.32), tint.withValues(alpha: 0)],
      stops: const [0, 0.7],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: w * 0.7));
    canvas.save();
    canvas.translate(w * 0.22, h * 0.40);
    canvas.scale(1, h / w);
    canvas.drawRect(
      Rect.fromLTWH(-w * 2, -h * 2, w * 4, h * 4),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoomTintPainter oldDelegate) => oldDelegate.tint != tint;
}

enum _BadgeMode { full, tablet, phone }

class _Badges extends StatelessWidget {
  const _Badges({required this.game, required this.mode});
  final GameEntry game;
  final _BadgeMode mode;

  @override
  Widget build(BuildContext context) {
    final system = systemLabel(game.system).toUpperCase();
    final size = fileSizeLabel(game.fileSize);
    final year = game.year;
    switch (mode) {
      case _BadgeMode.full:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(label: system, system: true),
            if (year != null) _Chip(label: '$year'),
            if (game.fileSize > 0) _Chip(label: size),
          ],
        );
      case _BadgeMode.tablet:
        final meta = [
          if (year != null) '$year',
          if (game.fileSize > 0) size,
        ].join(' · ');
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(label: system, system: true),
            if (meta.isNotEmpty) _Chip(label: meta),
          ],
        );
      case _BadgeMode.phone:
        final meta = [system, if (year != null) '$year'].join(' · ');
        return _Chip(
          label: meta,
          system: true,
          height: 26,
          pad: 10,
          fontSize: 11,
          tracking: 0.08,
        );
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.system = false,
    this.height = 28,
    this.pad = 12,
    this.fontSize = 12,
    this.tracking = 0.10,
  });
  final String label;
  final bool system;
  final double height;
  final double pad;
  final double fontSize;
  final double tracking;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: pad),
      decoration: BoxDecoration(
        color: system ? const Color(0x24007BFF) : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: system ? const Color(0x5C007BFF) : const Color(0x24DDE6F4),
        ),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: system
              ? Tokens.display(
                  size: fontSize,
                  weight: FontWeight.w600,
                  ls: tracking * fontSize,
                  color: Tokens.systemLabelFg,
                  height: 1,
                )
              : Tokens.body(
                  size: fontSize,
                  weight: FontWeight.w600,
                  color: const Color(0xFFC9D6E2),
                  height: 1,
                ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.title,
    required this.onBack,
    this.libraryOnly = false,
  });
  final String title;
  final VoidCallback onBack;
  final bool libraryOnly;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TapRow(
          onTap: onBack,
          child: Icon(Symbols.arrowBack, size: 18, color: Tokens.muted),
        ),
        const SizedBox(width: 6),
        _TapRow(
          onTap: onBack,
          child: Text(
            'Library',
            style: Tokens.body(
              size: 14,
              weight: FontWeight.w600,
              color: Tokens.muted,
              height: null,
            ),
          ),
        ),
        if (!libraryOnly) ...[
          const SizedBox(width: 8),
          Text(
            '/',
            style: Tokens.body(
              size: 14,
              weight: FontWeight.w600,
              color: Tokens.muted.withValues(alpha: 0.4),
              height: null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Tokens.body(
              size: 14,
              weight: FontWeight.w600,
              color: Tokens.text,
              height: null,
            ),
          ),
        ],
      ],
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.text,
    required this.size,
    required this.align,
    required this.maxLines,
  });
  final String text;
  final double size;
  final TextAlign align;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Tokens.display(
        size: size,
        weight: FontWeight.w700,
        ls: -0.035 * size,
        color: Colors.white,
        height: 0.95,
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Tokens.body(size: 13, color: Tokens.muted, height: 1.4),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.data,
    required this.compact,
    this.dense = false,
  });

  final _DetailData data;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cells = [
      _StatCell(
        label: 'Played',
        value: '—',
        tooltip: 'Playtime is not tracked yet',
        compact: compact,
      ),
      _StatCell(
        label: 'Last played',
        value: lastPlayedLabel(data.game.lastPlayedMs),
        compact: compact,
      ),
      _StatCell(
        label: 'Snapshots',
        value: '${data.saves.length}',
        tooltip: countLabel(data.saves.length, 'snapshot'),
        compact: compact,
      ),
      _StatCell(
        label: 'Core',
        value: data.coreName,
        warn: data.core == null,
        onTap: data.canChangeCore ? data.actions.core : null,
        tooltip: data.canChangeCore ? 'Choose core' : null,
        compact: compact,
      ),
    ];
    final pad = dense ? 12.0 : (compact ? 18.0 : 24.0);
    final row = Container(
      decoration: Tokens.statPanelDecor,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells.length; i++)
            Container(
              constraints: dense
                  ? null
                  : BoxConstraints(minWidth: compact ? 108 : 124),
              padding: EdgeInsets.symmetric(
                horizontal: pad,
                vertical: dense ? 9 : (compact ? 12 : 14),
              ),
              decoration: i == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0x14DDE6F4)),
                      ),
                    ),
              child: cells[i],
            ),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: row,
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.compact,
    this.warn = false,
    this.onTap,
    this.tooltip,
  });
  final String label;
  final String value;
  final bool compact;
  final bool warn;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: compact
              ? Tokens.body(
                  size: 11,
                  weight: FontWeight.w600,
                  ls: 0.08 * 11,
                  color: Tokens.muted,
                  height: 1.2,
                )
              : Tokens.statLabel,
        ),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? Tokens.statValue.copyWith(fontSize: 17)
                      : Tokens.statValue)
                  .copyWith(color: warn ? Tokens.warn : Tokens.text),
        ),
      ],
    );
    if (onTap == null && tooltip == null) return content;
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: content,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.data,
    required this.desktop,
    required this.t,
    required this.scale,
  });

  final _DetailData data;
  final bool desktop;
  final double t;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final height = 56.0;
    final resume = desktop ? 202.0 : _lerp(152, 185, t);
    final fromStart = desktop ? 181.0 : _lerp(150, 170, t);
    final cheats = desktop ? 173.0 : _lerp(150, 165, t);
    final fontSize = desktop ? 16.0 : 15.0;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ActionButton(
          label: data.primaryLabel,
          icon: Symbols.playArrow,
          glyph: desktop ? 'Enter' : null,
          primary: true,
          width: resume,
          height: height,
          fontSize: fontSize,
          onPressed: () => data.actions.play(data.hasAuto),
        ),
        if (data.hasAuto)
          _ActionButton(
            label: desktop ? 'Play from start' : 'From start',
            icon: Symbols.restartAlt,
            width: fromStart,
            height: height,
            fontSize: fontSize,
            onPressed: () => data.actions.play(false),
          ),
        _ActionButton(
          label: data.cheatsLabel(full: desktop),
          icon: Symbols.bolt,
          width: cheats,
          height: height,
          fontSize: fontSize,
          onPressed: data.actions.cheats,
        ),
        SizedBox(
          width: height,
          height: height,
          child: _FavouriteButton(
            favorite: data.game.favorite,
            onPressed: data.actions.favourite,
            size: height,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.width,
    this.height = 56,
    this.glyph,
    this.fontSize = 16,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double? width;
  final double height;
  final String? glyph;
  final double fontSize;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.onPressed == null
        ? OrbitButtonState.disabled
        : _hover
        ? OrbitButtonState.hover
        : OrbitButtonState.rest;
    final decoration = widget.primary
        ? Tokens.primaryButton(state: state, radius: Tokens.radiusPrimary)
        : Tokens.secondaryButton(state: state, radius: Tokens.radiusPrimary);
    final fg = widget.primary ? Colors.white : Tokens.text;
    final actionPad = widget.glyph != null
        ? 17.0
        : (widget.width != null ? math.min(18.0, widget.width! * 0.10) : 22.0);
    final gap = widget.fontSize >= 16 ? 9.0 : 8.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              width: widget.width,
              height: widget.height,
              padding: EdgeInsets.symmetric(horizontal: actionPad),
              decoration: decoration,
              child: Row(
                mainAxisSize: widget.width == null
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.glyph != null) ...[
                    Container(
                      height: 20,
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.glyph!,
                        style: Tokens.display(
                          size: 10.5,
                          weight: FontWeight.w700,
                          ls: 0,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                  ],
                  Icon(widget.icon, size: 21, color: fg, fill: 1),
                  SizedBox(width: gap),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: widget.fontSize,
                        weight: FontWeight.w600,
                        color: fg,
                        height: null,
                      ),
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

enum _HeartTone { plain, accent }

class _FavouriteButton extends StatefulWidget {
  const _FavouriteButton({
    required this.favorite,
    required this.onPressed,
    this.size = 44,
    this.tone = _HeartTone.plain,
  });
  final bool favorite;
  final VoidCallback onPressed;
  final double size;
  final _HeartTone tone;

  @override
  State<_FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends State<_FavouriteButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final state = _hover ? OrbitButtonState.hover : OrbitButtonState.rest;
    final accent = widget.tone == _HeartTone.accent;
    final ink = accent
        ? (widget.favorite ? Tokens.iconBlue : Tokens.text)
        : Tokens.text;
    return Tooltip(
      message: widget.favorite ? 'Remove from favourites' : 'Add to favourites',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(
              accent ? Tokens.radiusPill : Tokens.radiusMd,
            ),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              width: widget.size,
              height: widget.size,
              decoration: Tokens.secondaryButton(
                state: state,
                radius: accent ? Tokens.radiusPill : Tokens.radiusMd,
              ),
              child: Icon(
                Symbols.favorite,
                size: widget.size * 0.42,
                fill: widget.favorite ? 1 : 0,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 44,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              width: widget.size,
              height: widget.size,
              decoration: Tokens.secondaryButton(
                state: _hover ? OrbitButtonState.hover : OrbitButtonState.rest,
                radius: Tokens.radiusPill,
              ),
              child: Icon(
                widget.icon,
                size: widget.size * 0.45,
                color: Tokens.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SnapshotHeader extends StatelessWidget {
  const _SnapshotHeader({required this.showNote, required this.phone});
  final bool showNote;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Snapshots',
          style: Tokens.display(
            size: phone ? 17 : 19,
            weight: FontWeight.w600,
            ls: -0.01 * (phone ? 17 : 19),
            color: Colors.white,
            height: 1,
          ),
        ),
        if (showNote) ...[
          const Spacer(),
          Text(
            'Choose one to jump back in',
            style: Tokens.body(size: 13, color: Tokens.muted, height: null),
          ),
        ],
      ],
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.system,
    required this.saves,
    required this.width,
    required this.cardWidth,
    required this.thumbHeight,
    required this.showNames,
    required this.showSlotTags,
    required this.compactCaptions,
    required this.onLoad,
    required this.onMenu,
    this.phone = false,
  });

  final String system;
  final List<SaveSlot> saves;
  final double width;
  final double cardWidth;
  final double thumbHeight;
  final bool showNames;
  final bool showSlotTags;
  final bool compactCaptions;
  final ValueChanged<String> onLoad;
  final ValueChanged<SaveSlot> onMenu;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    if (saves.isEmpty) {
      return _EmptySnapshots(width: phone ? width : math.min(width, 560));
    }
    final gap = phone ? 14.0 : 16.0;
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < saves.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              _SnapshotCard(
                key: Key('snapshot-${saves[i].id}'),
                slot: saves[i],
                system: system,
                width: cardWidth,
                thumbHeight: thumbHeight,
                showName: showNames,
                showSlotTag: showSlotTags,
                compactCaption: compactCaptions,
                onLoad: () => onLoad(saves[i].id),
                onMenu: () => onMenu(saves[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatefulWidget {
  const _SnapshotCard({
    super.key,
    required this.slot,
    required this.system,
    required this.width,
    required this.thumbHeight,
    required this.showName,
    required this.showSlotTag,
    required this.compactCaption,
    required this.onLoad,
    required this.onMenu,
  });

  final SaveSlot slot;
  final String system;
  final double width;
  final double thumbHeight;
  final bool showName;
  final bool showSlotTag;
  final bool compactCaption;
  final VoidCallback onLoad;
  final VoidCallback onMenu;

  @override
  State<_SnapshotCard> createState() => _SnapshotCardState();
}

class _SnapshotCardState extends State<_SnapshotCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tag = widget.showSlotTag
        ? _slotTag(widget.slot.id)
        : snapshotTag(widget.slot.id);
    final tagColor = widget.showSlotTag
        ? _slotTagColor(widget.slot.id)
        : snapshotTagColor(widget.slot.id);
    final nameSize = widget.width >= 160 ? 15.0 : 13.0;
    final metaSize = widget.width >= 160 ? 13.0 : 12.0;
    return SizedBox(
      width: widget.width,
      child: GestureDetector(
        onLongPress: widget.onMenu,
        onSecondaryTap: widget.onMenu,
        child: Semantics(
          button: true,
          label: 'Load ${saveName(widget.slot.id)}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onLoad,
              borderRadius: BorderRadius.circular(10),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: Tokens.fastDur,
                      curve: Tokens.ease,
                      height: widget.thumbHeight,
                      width: widget.width,
                      transform: _hover
                          ? (Matrix4.identity()
                              ..translateByDouble(0, -2, 0, 1)
                              ..scaleByDouble(1.02, 1.02, 1, 1))
                          : Matrix4.identity(),
                      transformAlignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hover
                              ? Tokens.accent
                              : const Color(0x24DDE6F4),
                        ),
                        boxShadow: _hover
                            ? [
                                const BoxShadow(
                                  color: Tokens.focusHalo,
                                  blurRadius: 18,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _SnapshotStripes(
                                color: SystemHues.blockFor(widget.system),
                                period: widget.width >= 160 ? 8.2 : 9.6,
                              ),
                            ),
                            if (tag != null)
                              Positioned(
                                left: widget.width >= 160 ? 12 : 10,
                                top: widget.width >= 160 ? 11 : 10,
                                child: Container(
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xBF060B14),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Text(
                                    tag,
                                    style: Tokens.body(
                                      size: 11,
                                      weight: FontWeight.w700,
                                      color: tagColor,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.showName) ...[
                      Text(
                        saveName(widget.slot.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: nameSize,
                          weight: FontWeight.w700,
                          color: Tokens.text,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(
                      widget.compactCaption
                          ? snapshotWhen(widget.slot, compact: true)
                          : snapshotWhen(widget.slot),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: metaSize,
                        weight: FontWeight.w500,
                        color: const Color(0xFF8A9AA8),
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SnapshotStripes extends CustomPainter {
  _SnapshotStripes({required this.color, required this.period});
  final Color color;
  final double period;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Color.lerp(color, const Color(0xFF060B14), 0.34)!;
    final dark = Color.lerp(color, const Color(0xFF060B14), 0.52)!;
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final paint = Paint()..color = dark;
    final diag = size.width + size.height;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(45 * math.pi / 180);
    for (var x = -diag; x <= diag; x += period * 2) {
      canvas.drawRect(Rect.fromLTWH(x, -diag, period, diag * 2), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SnapshotStripes oldDelegate) =>
      oldDelegate.color != color || oldDelegate.period != period;
}

class _EmptySnapshots extends StatelessWidget {
  const _EmptySnapshots({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 110,
      child: CustomPaint(
        foregroundPainter: const _DashedRoundedBorder(color: Color(0x24DDE6F4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No snapshots yet. ezCORE takes one automatically every time you '
              'stop playing.',
              style: Tokens.body(size: 15, color: Tokens.muted, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed 1.5 px rounded outline for the empty-snapshots box.
class _DashedRoundedBorder extends CustomPainter {
  const _DashedRoundedBorder({required this.color});

  final Color color;

  static const _radius = 10.0;
  static const _strokeWidth = 1.5;
  static const _dash = 7.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(_strokeWidth / 2),
          const Radius.circular(_radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + _dash, metric.length)),
          paint,
        );
        at += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorder oldDelegate) =>
      oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Generated cover in its room
// ---------------------------------------------------------------------------

class _CoverArt extends StatefulWidget {
  const _CoverArt({
    required this.game,
    required this.width,
    this.yaw = 14,
    this.pitch = 3,
    this.interactive = false,
    this.shadow = true,
  });

  final GameEntry game;
  final double width;
  final double yaw;
  final double pitch;
  final bool interactive;
  final bool shadow;

  @override
  State<_CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<_CoverArt> {
  Offset _tilt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final height = width * 4 / 3;
    final tx = _tilt.dx;
    final ty = _tilt.dy;
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, -1 / 1100)
      ..rotateY((widget.yaw + tx * 16) * math.pi / 180)
      ..rotateX((widget.pitch - ty * 12) * math.pi / 180);
    final glare = Alignment(
      tx.clamp(-1.0, 1.0),
      (-0.4 + ty * 0.8).clamp(-1.0, 1.0),
    );
    final content = Transform(
      alignment: Alignment.center,
      transform: matrix,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OrbitCover(
              title: _balancedTitle(
                widget.game.title,
                width * 0.13,
                width * 0.86,
              ),
              systemId: widget.game.system,
              sysShort: systemCode(widget.game.system),
              year: widget.game.year,
              radius: 8,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: glare,
                        radius: 0.9,
                        colors: [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.7],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final framed = SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.shadow)
            Positioned(
              left: -width * 0.10,
              top: height * 0.04,
              width: width * 1.20,
              height: height * 1.06,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.52, 0.68),
                    radius: 0.52,
                    colors: [
                      Colors.black.withValues(alpha: 0.62),
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.52, 1],
                  ),
                ),
              ),
            ),
          Positioned.fill(child: content),
          if (widget.shadow)
            Positioned(
              left: width * 0.1,
              right: width * 0.1,
              bottom: -width * (22 / 360),
              height: width * (30 / 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: RadialGradient(
                    radius: 0.5,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.85],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!widget.interactive) return framed;
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(e.position);
        final next = Offset(
          (local.dx / box.size.width - 0.5) * 2,
          (local.dy / box.size.height - 0.5) * 2,
        );
        setState(() => _tilt = next);
      },
      onExit: (_) => setState(() => _tilt = Offset.zero),
      child: framed,
    );
  }
}

// ---------------------------------------------------------------------------
// Save-slot naming (display only)
// ---------------------------------------------------------------------------

/// How a save slot is named to people.
String saveName(String slot) {
  if (slot == autoSlot) return 'Autosave';
  if (slot == 'slot0') return 'Quick save';
  if (slot == 'recovered') return 'Recovered';
  final stamped = RegExp(r'^slot-(\d{2})(\d{2})(\d{2})$').firstMatch(slot);
  if (stamped != null) {
    return 'Saved ${stamped[1]}:${stamped[2]}:${stamped[3]}';
  }
  final numbered = RegExp(r'^slot-?(\d+)$').firstMatch(slot);
  if (numbered != null) {
    final n = int.tryParse(numbered[1]!);
    if (n != null) return 'Slot $n';
  }
  return slot;
}

/// The small pill on a snapshot thumb.
String? snapshotTag(String slot) {
  if (slot == autoSlot) return 'Auto';
  if (slot == 'slot0') return 'Quick';
  if (slot == 'recovered') return 'Crash-safe';
  return null;
}

/// The tag's ink: Auto blue, Crash-safe amber, everything else text.
Color snapshotTagColor(String slot) {
  if (slot == autoSlot) return Tokens.systemLabelFg;
  if (slot == 'recovered') return Tokens.warn;
  return Tokens.text;
}

String? _slotTag(String slot) {
  final tag = snapshotTag(slot);
  if (tag != null) return tag;
  return saveName(slot);
}

Color _slotTagColor(String slot) => snapshotTagColor(slot);

/// "when you stopped" for the automatic slot, otherwise a compact age.
///
/// The desktop card carries the slot name above this line, so the age there
/// keeps the time ("Yesterday 21:30"). The smaller families use the compact
/// form ("Yesterday"), matching the device renders.
String snapshotWhen(SaveSlot slot, {bool compact = false}) {
  if (slot.id == autoSlot) return 'when you stopped';
  final then = slot.modified.toLocal();
  final now = DateTime.now();
  final diff = now.difference(then);
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  final hh = then.hour.toString().padLeft(2, '0');
  final mm = then.minute.toString().padLeft(2, '0');
  final day = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(then.year, then.month, then.day);
  final days = day.difference(thatDay).inDays;
  if (days == 1) return compact ? 'Yesterday' : 'Yesterday $hh:$mm';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inHours < 12) return '${diff.inHours} hr ago';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'Last week';
  if (days < 60) return '${(days / 7).floor()} wk ago';
  return '${then.year}-${then.month.toString().padLeft(2, '0')}-'
      '${then.day.toString().padLeft(2, '0')}';
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The design balances a cover title across lines (`text-wrap: balance`), so
/// "Lanterns of Vell" sets as "Lanterns" / "of Vell" instead of "Lanterns of"
/// / "Vell". Flutter wraps greedily, so pick the split with the narrowest
/// widest line.
String _balancedTitle(String title, double fontSize, double maxWidth) {
  final words = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length < 2) return title;
  final style = TextStyle(
    fontFamily: Tokens.displayFamily,
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.03 * fontSize,
  );
  double measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  if (measure(title) <= maxWidth) return title;
  var best = title;
  var bestWidest = double.infinity;
  for (var i = 1; i < words.length; i++) {
    final a = words.sublist(0, i).join(' ');
    final b = words.sublist(i).join(' ');
    final widest = math.max(measure(a), measure(b));
    if (widest < bestWidest) {
      bestWidest = widest;
      best = '$a\n$b';
    }
  }
  return best;
}
