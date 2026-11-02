import 'dart:math' as math;
import 'dart:ui' as ui;

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
/// The screen renders only its own content: the room tint, the tilted cover,
/// the information column, the actions and the snapshots. The OS bar, rail,
/// backdrop and hint row belong to the shell.
///
/// Layout follows [Layout.ofSize]:
/// - desktop: the 1440×900 composition (cover at 150/150, right column at
///   600/120), interpolated down to the 1180-wide composition where the
///   breadcrumb moves above the cover and the cover gives the left third;
/// - tablet: a two-column composition when there is room, otherwise the
///   stacked column;
/// - tablet portrait: cover, title and thumb-zone actions in one column;
/// - phones: the 3a stack with ×0.85 type and a horizontally scrolling
///   snapshot row.
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
                      final content = _content(
                        context,
                        game,
                        saves,
                        cores,
                        cheatsOn,
                        layout,
                        c.maxWidth,
                        c.maxHeight,
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
    BuildContext context,
    GameEntry game,
    List<SaveSlot> saves,
    List<CoreManifest> cores,
    int cheatsOn,
    OrbitLayout layout,
    double width,
    double height,
  ) {
    if (layout == OrbitLayout.phonePortrait) {
      return _PhonePortrait(
        game: game,
        saves: saves,
        cheatsOn: cheatsOn,
        width: width,
        topInset: MediaQuery.of(context).padding.top,
        bottomInset: MediaQuery.of(context).padding.bottom,
        onBack: _back,
        onPlay: (resume) => _play(game, resume: resume),
        onPlaySlot: (id) => _play(game, slot: id),
        onCheats: () => _openCheats(game),
        onFavourite: () => state.toggleFavorite(game.id),
        onSnapshotMenu: _snapshotMenu,
      );
    }
    if (layout == OrbitLayout.phoneLandscape) {
      return _PhoneLandscape(
        game: game,
        saves: saves,
        cores: cores,
        cheatsOn: cheatsOn,
        onBack: _back,
        onPlay: (resume) => _play(game, resume: resume),
        onPlaySlot: (id) => _play(game, slot: id),
        onCheats: () => _openCheats(game),
        onFavourite: () => state.toggleFavorite(game.id),
        onCore: cores.length > 1 ? () => _chooseCore(game, cores) : null,
        onSnapshotMenu: _snapshotMenu,
      );
    }
    if (layout == OrbitLayout.tabletPortrait) {
      return _Stacked(
        game: game,
        saves: saves,
        cores: cores,
        cheatsOn: cheatsOn,
        width: width,
        titleSize: 44,
        coverWidth: math.min(280, width * 0.42),
        onBack: _back,
        onPlay: (resume) => _play(game, resume: resume),
        onPlaySlot: (id) => _play(game, slot: id),
        onCheats: () => _openCheats(game),
        onFavourite: () => state.toggleFavorite(game.id),
        onCore: cores.length > 1 ? () => _chooseCore(game, cores) : null,
        onSnapshotMenu: _snapshotMenu,
      );
    }
    // Tablet and desktop share the two-column composition. Below 1080 the
    // right column can no longer hold the stat strip, so the stacked column
    // is the honest fallback.
    if (width >= 1080) {
      return _Wide(
        game: game,
        saves: saves,
        cores: cores,
        cheatsOn: cheatsOn,
        width: width,
        height: height,
        layout: layout,
        onBack: _back,
        onPlay: (resume) => _play(game, resume: resume),
        onPlaySlot: (id) => _play(game, slot: id),
        onCheats: () => _openCheats(game),
        onFavourite: () => state.toggleFavorite(game.id),
        onCore: cores.length > 1 ? () => _chooseCore(game, cores) : null,
        onSnapshotMenu: _snapshotMenu,
      );
    }
    return _Stacked(
      game: game,
      saves: saves,
      cores: cores,
      cheatsOn: cheatsOn,
      width: width,
      titleSize: 40,
      coverWidth: math.min(250, width * 0.36),
      onBack: _back,
      onPlay: (resume) => _play(game, resume: resume),
      onPlaySlot: (id) => _play(game, slot: id),
      onCheats: () => _openCheats(game),
      onFavourite: () => state.toggleFavorite(game.id),
      onCore: cores.length > 1 ? () => _chooseCore(game, cores) : null,
      onSnapshotMenu: _snapshotMenu,
    );
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
// Wide composition (desktop and tablet landscape)
// ---------------------------------------------------------------------------

class _Wide extends StatelessWidget {
  const _Wide({
    required this.game,
    required this.saves,
    required this.cores,
    required this.cheatsOn,
    required this.width,
    required this.height,
    required this.layout,
    required this.onBack,
    required this.onPlay,
    required this.onPlaySlot,
    required this.onCheats,
    required this.onFavourite,
    required this.onCore,
    required this.onSnapshotMenu,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final List<CoreManifest> cores;
  final int cheatsOn;
  final double width;
  final double height;
  final OrbitLayout layout;
  final VoidCallback onBack;
  final ValueChanged<bool> onPlay;
  final ValueChanged<String> onPlaySlot;
  final VoidCallback onCheats;
  final VoidCallback onFavourite;
  final VoidCallback? onCore;
  final ValueChanged<SaveSlot> onSnapshotMenu;

  @override
  Widget build(BuildContext context) {
    // The design is drawn at 1440×900. At 1180 the breadcrumb moves above
    // the cover and the cover gives the left third. Everything in between is
    // interpolated so one screen covers both references.
    final t = ((width - 1180) / 260).clamp(0.0, 1.0);
    final desktop = layout == OrbitLayout.desktop;
    final topBreadcrumb = !desktop || t < 0.35;

    final left = _lerp(53, 139, t);
    final top = _lerp(93, 150, t);
    final coverWidth = _lerp(296, 360, t);
    final rightX = left + coverWidth + _lerp(92, 101, t);
    final rightTop = _lerp(104, 120, t);
    final rightMargin = _lerp(155, 80, t);
    final rightWidth = math.max(320.0, width - rightX - rightMargin);
    final titleSize = _lerp(62, 76, t);
    final buttonScale = (rightWidth / 760).clamp(0.68, 1.0);
    final showNames = width >= 1360;
    final showNote = width >= 1360 && !topBreadcrumb;

    final designHeight = math.max(height, 780.0);
    return SingleChildScrollView(
      child: SizedBox(
        height: designHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              top: top,
              child: _TiltedCover(game: game, width: coverWidth),
            ),
            Positioned(
              left: rightX,
              top: rightTop,
              right: rightMargin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!topBreadcrumb) ...[
                    _Breadcrumb(
                      title: game.title,
                      onBack: onBack,
                      compact: false,
                    ),
                    const SizedBox(height: 33),
                  ],
                  _Badges(game: game, compact: false),
                  const SizedBox(height: 16),
                  _Title(text: game.title, size: titleSize, center: false),
                  SizedBox(height: _lerp(18, 21, t)),
                  _StatsStrip(
                    game: game,
                    saves: saves,
                    core: _coreFor(),
                    onCore: onCore,
                    compact: width < 1240,
                  ),
                  SizedBox(height: _lerp(12, 22, t)),
                  _Actions(
                    game: game,
                    saves: saves,
                    cheatsOn: cheatsOn,
                    scale: buttonScale,
                    onPlay: onPlay,
                    onCheats: onCheats,
                    onFavourite: onFavourite,
                  ),
                  SizedBox(height: _lerp(28, 44, t)),
                  _SnapshotHeader(count: saves.length, showNote: showNote),
                  SizedBox(height: _lerp(14, 19, t)),
                  _SnapshotRow(
                    system: game.system,
                    saves: saves,
                    width: rightWidth,
                    cardWidth: 178,
                    thumbHeight: 110,
                    showNames: showNames,
                    onLoad: onPlaySlot,
                    onMenu: onSnapshotMenu,
                  ),
                ],
              ),
            ),
            if (topBreadcrumb)
              Positioned(
                left: _lerp(44, 60, t),
                top: 28,
                child: _Breadcrumb(
                  title: game.title,
                  onBack: onBack,
                  compact: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  CoreManifest? _coreFor() {
    final byId = cores.where((m) => m.id == game.coreId).firstOrNull;
    if (byId != null) return byId;
    return cores.isEmpty ? null : cores.first;
  }
}

// ---------------------------------------------------------------------------
// Stacked composition (tablet portrait, small windows)
// ---------------------------------------------------------------------------

class _Stacked extends StatelessWidget {
  const _Stacked({
    required this.game,
    required this.saves,
    required this.cores,
    required this.cheatsOn,
    required this.width,
    required this.titleSize,
    required this.coverWidth,
    required this.onBack,
    required this.onPlay,
    required this.onPlaySlot,
    required this.onCheats,
    required this.onFavourite,
    required this.onCore,
    required this.onSnapshotMenu,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final List<CoreManifest> cores;
  final int cheatsOn;
  final double width;
  final double titleSize;
  final double coverWidth;
  final VoidCallback onBack;
  final ValueChanged<bool> onPlay;
  final ValueChanged<String> onPlaySlot;
  final VoidCallback onCheats;
  final VoidCallback onFavourite;
  final VoidCallback? onCore;
  final ValueChanged<SaveSlot> onSnapshotMenu;

  @override
  Widget build(BuildContext context) {
    final side = width >= 700 ? 44.0 : 24.0;
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
                  onPressed: onBack,
                ),
                const Spacer(),
                _FavouriteButton(
                  favorite: game.favorite,
                  onPressed: onFavourite,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: _TiltedCover(game: game, width: coverWidth),
            ),
            const SizedBox(height: 32),
            Center(child: _Badges(game: game, compact: false)),
            const SizedBox(height: 18),
            Center(
              child: _Title(text: game.title, size: titleSize, center: true),
            ),
            const SizedBox(height: 10),
            Center(
              child: _MetaLine(game: game, saves: saves),
            ),
            const SizedBox(height: 26),
            Center(
              child: _StatsStrip(
                game: game,
                saves: saves,
                core: _coreFor(),
                onCore: onCore,
                compact: true,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: _actionChildren(),
            ),
            const SizedBox(height: 34),
            _SnapshotHeader(count: saves.length, showNote: false),
            const SizedBox(height: 14),
            _SnapshotRow(
              system: game.system,
              saves: saves,
              width: width - side * 2,
              cardWidth: 178,
              thumbHeight: 110,
              showNames: saves.isNotEmpty,
              onLoad: onPlaySlot,
              onMenu: onSnapshotMenu,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionChildren() {
    final hasAuto = saves.any((s) => s.id == autoSlot);
    return [
      _ActionButton(
        label: hasAuto ? 'Resume' : 'Play',
        icon: Symbols.playArrow,
        primary: true,
        width: 210,
        height: 52,
        onPressed: () => onPlay(hasAuto),
      ),
      if (hasAuto)
        _ActionButton(
          label: 'Play from start',
          icon: Symbols.restartAlt,
          width: 186,
          height: 52,
          onPressed: () => onPlay(false),
        ),
      _ActionButton(
        label: _cheatsLabel(),
        icon: Symbols.bolt,
        width: 172,
        height: 52,
        onPressed: onCheats,
      ),
      SizedBox(
        width: 52,
        height: 52,
        child: _FavouriteButton(
          favorite: game.favorite,
          onPressed: onFavourite,
        ),
      ),
    ];
  }

  CoreManifest? _coreFor() {
    final byId = cores.where((m) => m.id == game.coreId).firstOrNull;
    if (byId != null) return byId;
    return cores.isEmpty ? null : cores.first;
  }

  String _cheatsLabel() => cheatsOn > 0 ? 'Cheats · $cheatsOn' : 'Cheats';
}

// ---------------------------------------------------------------------------
// Phone portrait (3a)
// ---------------------------------------------------------------------------

class _PhonePortrait extends StatelessWidget {
  const _PhonePortrait({
    required this.game,
    required this.saves,
    required this.cheatsOn,
    required this.width,
    required this.topInset,
    required this.bottomInset,
    required this.onBack,
    required this.onPlay,
    required this.onPlaySlot,
    required this.onCheats,
    required this.onFavourite,
    required this.onSnapshotMenu,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final int cheatsOn;
  final double width;
  final double topInset;
  final double bottomInset;
  final VoidCallback onBack;
  final ValueChanged<bool> onPlay;
  final ValueChanged<String> onPlaySlot;
  final VoidCallback onCheats;
  final VoidCallback onFavourite;
  final ValueChanged<SaveSlot> onSnapshotMenu;

  @override
  Widget build(BuildContext context) {
    final hasAuto = saves.any((s) => s.id == autoSlot);
    final s = (width / 390).clamp(0.82, 1.1);
    final side = 22.0 * s;
    final coverWidth = 162.0 * s;
    final cardWidth = 143.0 * s;
    final cardHeight = 90.0 * s;
    // The design's status bar is part of the device frame, so the content
    // starts 48 px below the safe area on every phone.
    final top = topInset + 48;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(side, top, side, bottomInset + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36 + coverWidth * 4 / 3,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: _RoundButton(
                    tooltip: 'Back',
                    icon: Symbols.arrowBack,
                    size: 44 * s,
                    onPressed: onBack,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: _FavouriteButton(
                    favorite: game.favorite,
                    onPressed: onFavourite,
                    size: 44 * s,
                  ),
                ),
                Positioned(
                  left: (width - side * 2 - coverWidth) / 2,
                  top: 36 * s,
                  child: _TiltedCover(game: game, width: coverWidth),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(child: _Badges(game: game, compact: true)),
          const SizedBox(height: 19),
          Center(
            child: _Title(text: game.title, size: 36 * s, center: true),
          ),
          const SizedBox(height: 7),
          Center(
            child: _MetaLine(game: game, saves: saves),
          ),
          const SizedBox(height: 30),
          _ActionButton(
            label: hasAuto ? 'Resume' : 'Play',
            icon: Symbols.playArrow,
            primary: true,
            height: 60 * s,
            onPressed: () => onPlay(hasAuto),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (hasAuto) ...[
                Expanded(
                  child: _ActionButton(
                    label: 'From start',
                    icon: Symbols.restartAlt,
                    height: 60 * s,
                    onPressed: () => onPlay(false),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _ActionButton(
                  label: _cheatsLabel(),
                  icon: Symbols.bolt,
                  height: 60 * s,
                  onPressed: onCheats,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _SnapshotHeader(count: saves.length, showNote: false, phone: true),
          const SizedBox(height: 9),
          _SnapshotRow(
            system: game.system,
            saves: saves,
            width: width - side * 2,
            cardWidth: cardWidth,
            thumbHeight: cardHeight,
            showNames: false,
            onLoad: onPlaySlot,
            onMenu: onSnapshotMenu,
            phone: true,
          ),
        ],
      ),
    );
  }

  String _cheatsLabel() => cheatsOn > 0 ? 'Cheats · $cheatsOn' : 'Cheats';
}

// ---------------------------------------------------------------------------
// Phone landscape
// ---------------------------------------------------------------------------

class _PhoneLandscape extends StatelessWidget {
  const _PhoneLandscape({
    required this.game,
    required this.saves,
    required this.cores,
    required this.cheatsOn,
    required this.onBack,
    required this.onPlay,
    required this.onPlaySlot,
    required this.onCheats,
    required this.onFavourite,
    required this.onCore,
    required this.onSnapshotMenu,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final List<CoreManifest> cores;
  final int cheatsOn;
  final VoidCallback onBack;
  final ValueChanged<bool> onPlay;
  final ValueChanged<String> onPlaySlot;
  final VoidCallback onCheats;
  final VoidCallback onFavourite;
  final VoidCallback? onCore;
  final ValueChanged<SaveSlot> onSnapshotMenu;

  @override
  Widget build(BuildContext context) {
    final hasAuto = saves.any((s) => s.id == autoSlot);
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
                _TiltedCover(game: game, width: coverWidth),
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
                            onPressed: onBack,
                          ),
                          const Spacer(),
                          _FavouriteButton(
                            favorite: game.favorite,
                            onPressed: onFavourite,
                            size: 36,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _Badges(game: game, compact: true),
                      const SizedBox(height: 10),
                      _Title(text: game.title, size: 30, center: false),
                      const SizedBox(height: 4),
                      _MetaLine(game: game, saves: saves),
                      const SizedBox(height: 12),
                      _StatsStrip(
                        game: game,
                        saves: saves,
                        core: _coreFor(),
                        onCore: onCore,
                        compact: true,
                        dense: true,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ActionButton(
                            label: hasAuto ? 'Resume' : 'Play',
                            icon: Symbols.playArrow,
                            primary: true,
                            width: 168,
                            height: 44,
                            onPressed: () => onPlay(hasAuto),
                          ),
                          if (hasAuto)
                            _ActionButton(
                              label: 'From start',
                              icon: Symbols.restartAlt,
                              width: 148,
                              height: 44,
                              onPressed: () => onPlay(false),
                            ),
                          _ActionButton(
                            label: _cheatsLabel(),
                            icon: Symbols.bolt,
                            width: 138,
                            height: 44,
                            onPressed: onCheats,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SnapshotHeader(
                        count: saves.length,
                        showNote: false,
                        phone: true,
                      ),
                      const SizedBox(height: 6),
                      _SnapshotRow(
                        system: game.system,
                        saves: saves,
                        width: c.maxWidth - pad * 2 - coverWidth - 26,
                        cardWidth: 116,
                        thumbHeight: 64,
                        showNames: false,
                        onLoad: onPlaySlot,
                        onMenu: onSnapshotMenu,
                        phone: true,
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

  CoreManifest? _coreFor() {
    final byId = cores.where((m) => m.id == game.coreId).firstOrNull;
    if (byId != null) return byId;
    return cores.isEmpty ? null : cores.first;
  }

  String _cheatsLabel() => cheatsOn > 0 ? 'Cheats · $cheatsOn' : 'Cheats';
}

// ---------------------------------------------------------------------------
// Shared parts
// ---------------------------------------------------------------------------

class _RoomTint extends StatelessWidget {
  const _RoomTint({required this.system});
  final String system;

  @override
  Widget build(BuildContext context) {
    final tint = SystemHues.roomTintFor(system);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.56, -0.2),
            radius: 0.9,
            colors: [tint.withValues(alpha: 0.32), tint.withValues(alpha: 0)],
            stops: const [0, 0.7],
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
    required this.compact,
  });
  final String title;
  final VoidCallback onBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TapRow(
          onTap: onBack,
          child: Icon(Symbols.arrowBack, size: 18, color: Tokens.muted),
        ),
        const SizedBox(width: 10),
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
        if (!compact) ...[
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

class _Badges extends StatelessWidget {
  const _Badges({required this.game, required this.compact});
  final GameEntry game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final system = systemLabel(game.system).toUpperCase();
    final size = fileSizeLabel(game.fileSize);
    final year = game.year;
    if (compact) {
      final parts = [system, if (year != null) '$year'];
      return _Chip(
        label: parts.join(' · '),
        system: true,
        height: 21,
        size: 12,
        pad: 21,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(label: system, system: true),
        if (year != null) _Chip(label: '$year'),
        if (game.fileSize > 0) _Chip(label: size),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.system = false,
    this.height = 28,
    this.size = 12,
    this.pad = 10,
  });
  final String label;
  final bool system;
  final double height;
  final double size;
  final double pad;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: pad),
      decoration: BoxDecoration(
        color: system ? Tokens.systemLabelBg : null,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: system ? Tokens.systemLabelBd : const Color(0x24DDE6F4),
        ),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: system
              ? Tokens.display(
                  size: size,
                  weight: FontWeight.w600,
                  ls: 0.10 * size,
                  color: Tokens.systemLabelFg,
                  height: 1,
                )
              : Tokens.body(
                  size: size,
                  weight: FontWeight.w600,
                  color: Tokens.muted,
                  height: 1,
                ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.text, required this.size, required this.center});
  final String text;
  final double size;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      maxLines: 2,
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
  const _MetaLine({required this.game, required this.saves});
  final GameEntry game;
  final List<SaveSlot> saves;

  @override
  Widget build(BuildContext context) {
    final last = game.lastPlayedMs > 0
        ? 'Last played ${lastPlayedLabel(game.lastPlayedMs).toLowerCase()}'
        : 'Not played yet';
    return Text(
      '$last · ${countLabel(saves.length, 'snapshot')}',
      textAlign: TextAlign.center,
      maxLines: 2,
      style: Tokens.body(size: 13, color: Tokens.muted, height: 1.4),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.game,
    required this.saves,
    required this.core,
    required this.onCore,
    required this.compact,
    this.dense = false,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final CoreManifest? core;
  final VoidCallback? onCore;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cells = [
      _StatCell(
        label: 'Played',
        value: '—',
        tooltip: 'Playtime is not tracked yet',
      ),
      _StatCell(
        label: 'Last played',
        value: lastPlayedLabel(game.lastPlayedMs),
      ),
      _StatCell(
        label: 'Snapshots',
        value: '${saves.length}',
        tooltip: countLabel(saves.length, 'snapshot'),
      ),
      _StatCell(
        label: 'Core',
        value: core?.name ?? 'No core',
        warn: core == null,
        onTap: onCore,
        tooltip: onCore != null ? 'Choose core' : null,
      ),
    ];
    final pad = dense ? 12.0 : (compact ? 20.0 : 24.0);
    final row = Container(
      decoration: Tokens.statPanelDecor,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells.length; i++)
            Container(
              constraints: dense
                  ? null
                  : BoxConstraints(minWidth: compact ? 118 : 130),
              padding: EdgeInsets.symmetric(
                horizontal: pad,
                vertical: dense ? 9 : 14,
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
    this.warn = false,
    this.onTap,
    this.tooltip,
  });
  final String label;
  final String value;
  final bool warn;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: Tokens.statLabel),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tokens.statValue.copyWith(
            color: warn ? Tokens.warn : Tokens.text,
          ),
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

class _Actions extends StatelessWidget {
  const _Actions({
    required this.game,
    required this.saves,
    required this.cheatsOn,
    required this.scale,
    required this.onPlay,
    required this.onCheats,
    required this.onFavourite,
  });

  final GameEntry game;
  final List<SaveSlot> saves;
  final int cheatsOn;
  final double scale;
  final ValueChanged<bool> onPlay;
  final VoidCallback onCheats;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    final hasAuto = saves.any((s) => s.id == autoSlot);
    final height = 56.0;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ActionButton(
          label: hasAuto ? 'Resume' : 'Play',
          icon: Symbols.playArrow,
          glyph: 'Enter',
          primary: true,
          width: scale >= 0.95 ? 203 : 210 * scale,
          height: height,
          fontSize: _buttonType(scale),
          onPressed: () => onPlay(hasAuto),
        ),
        if (hasAuto)
          _ActionButton(
            label: scale < 0.95 ? 'From start' : 'Play from start',
            icon: Symbols.restartAlt,
            width: 186 * scale,
            height: height,
            fontSize: _buttonType(scale),
            onPressed: () => onPlay(false),
          ),
        _ActionButton(
          label: _cheatsLabel(),
          icon: Symbols.bolt,
          width: 172 * scale,
          height: height,
          fontSize: _buttonType(scale),
          onPressed: onCheats,
        ),
        SizedBox(
          width: height,
          height: height,
          child: _FavouriteButton(
            favorite: game.favorite,
            onPressed: onFavourite,
            size: height,
          ),
        ),
      ],
    );
  }

  String _cheatsLabel() => cheatsOn > 0 ? 'Cheats · $cheatsOn' : 'Cheats';

  double _buttonType(double scale) =>
      13 + 2.6 * ((scale - 0.68) / 0.32).clamp(0.0, 1.0);
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
    this.fontSize,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double? width;
  final double height;
  final String? glyph;
  final double? fontSize;

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
    final labelSize =
        widget.fontSize ?? math.min(16.0, math.max(13.0, widget.height * 0.29));
    final actionPad = math.min(18.0, (widget.width ?? 203) * 0.09);
    final gap = widget.width != null && widget.width! < 190 ? 6.0 : 10.0;
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
                      height: 24,
                      constraints: const BoxConstraints(minWidth: 26),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
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
                  Icon(widget.icon, size: 22, color: fg, fill: 1),
                  SizedBox(width: gap),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: labelSize,
                        weight: FontWeight.w700,
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

class _FavouriteButton extends StatefulWidget {
  const _FavouriteButton({
    required this.favorite,
    required this.onPressed,
    this.size = 44,
  });
  final bool favorite;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends State<_FavouriteButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final state = _hover ? OrbitButtonState.hover : OrbitButtonState.rest;
    return Tooltip(
      message: widget.favorite ? 'Remove from favourites' : 'Add to favourites',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              width: widget.size,
              height: widget.size,
              decoration: Tokens.secondaryButton(
                state: state,
                radius: widget.size >= 52
                    ? Tokens.radiusPrimary
                    : Tokens.radiusPill,
              ),
              child: Icon(
                Symbols.favorite,
                size: widget.size * 0.4,
                fill: widget.favorite ? 1 : 0,
                color: Tokens.text,
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
  const _SnapshotHeader({
    required this.count,
    required this.showNote,
    this.phone = false,
  });
  final int count;
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
            size: phone ? 20 : 19,
            weight: FontWeight.w600,
            ls: -0.01 * 19,
            color: Colors.white,
            height: 1,
          ),
        ),
        if (showNote) ...[
          const SizedBox(width: 16),
          const Spacer(),
          Text(
            count > 0
                ? 'Choose one to jump back in'
                : 'One is taken automatically',
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
  final ValueChanged<String> onLoad;
  final ValueChanged<SaveSlot> onMenu;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    if (saves.isEmpty) {
      return _EmptySnapshots(width: phone ? width : math.min(width, 560));
    }
    final gap = phone ? 8.0 : (showNames ? 16.0 : 18.0);
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
    required this.onLoad,
    required this.onMenu,
  });

  final SaveSlot slot;
  final String system;
  final double width;
  final double thumbHeight;
  final bool showName;
  final VoidCallback onLoad;
  final VoidCallback onMenu;

  @override
  State<_SnapshotCard> createState() => _SnapshotCardState();
}

class _SnapshotCardState extends State<_SnapshotCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tag = snapshotTag(widget.slot.id);
    final tagColor = snapshotTagColor(widget.slot.id);
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
                              : const Color(0x14DDE6F4),
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
                                period: math.max(8, widget.width / 178 * 14),
                              ),
                            ),
                            if (tag != null)
                              Positioned(
                                left: 8,
                                top: 8,
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
                    if (widget.showName)
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
                    if (widget.showName) const SizedBox(height: 3),
                    Text(
                      snapshotWhen(widget.slot),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: metaSize,
                        color: Tokens.muted,
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
    final light = Color.lerp(color, const Color(0xFF060B14), 0.22)!;
    final dark = Color.lerp(color, const Color(0xFF060B14), 0.42)!;
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final paint = Paint()..color = dark;
    final diag = size.width + size.height;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-45 * math.pi / 180);
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
    return Container(
      width: width,
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x24DDE6F4), width: 1.5),
      ),
      child: Text(
        'No snapshots yet. ezCORE takes one automatically every time you '
        'stop playing.',
        style: Tokens.body(size: 15, color: Tokens.muted, height: 1.5),
      ),
    );
  }
}

class _TiltedCover extends StatefulWidget {
  const _TiltedCover({required this.game, required this.width});
  final GameEntry game;
  final double width;

  @override
  State<_TiltedCover> createState() => _TiltedCoverState();
}

class _TiltedCoverState extends State<_TiltedCover> {
  Offset _tilt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 4 / 3;
    final tx = _tilt.dx;
    final ty = _tilt.dy;
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 1 / 1100)
      ..rotateY((14 + tx * 16) * math.pi / 180)
      ..rotateX((3 - ty * 12) * math.pi / 180);
    final glare = Alignment(
      tx.clamp(-1.0, 1.0),
      (-0.4 + ty * 0.8).clamp(-1.0, 1.0),
    );
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
      child: SizedBox(
        width: widget.width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xE6000000),
                      offset: Offset(-30, 50),
                      blurRadius: 90,
                      spreadRadius: -24,
                    ),
                  ],
                ),
                child: SizedBox(
                  width: widget.width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      OrbitCover(
                        title: _balancedTitle(
                          widget.game.title,
                          widget.width * 0.13,
                          widget.width * 0.86,
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
              ),
            ),
            Positioned(
              left: widget.width * 0.08,
              right: widget.width * 0.08,
              bottom: -widget.width * 0.11,
              height: widget.width * 0.11,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: RadialGradient(
                      radius: 0.6,
                      colors: [
                        Colors.black.withValues(alpha: 0.38),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.9],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
  final numbered = RegExp(r'^slot-?(\d+)$').firstMatch(slot);
  if (numbered != null) {
    final n = int.tryParse(numbered[1]!);
    if (n != null) return 'Slot $n';
  }
  return null;
}

/// The tag's ink: Auto blue, Crash-safe amber, everything else text.
Color snapshotTagColor(String slot) {
  if (slot == autoSlot) return Tokens.systemLabelFg;
  if (slot == 'recovered') return Tokens.warn;
  return Tokens.text;
}

/// "when you stopped" for the automatic slot, otherwise a compact age.
///
/// Saves older than twelve hours show "Yesterday 21:30" and "Last week",
/// matching the design's snapshot copy without inventing a value.
String snapshotWhen(SaveSlot slot) {
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
  if (days == 1) return 'Yesterday $hh:$mm';
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
/// widest line instead.
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
