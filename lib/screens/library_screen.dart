import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/system_labels.dart';
import '../models/game_entry.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';
import 'player_screen.dart';

/// Orbit Library — CoverFlow + bottom game dock (final-01),
/// with all legacy library functionality preserved:
/// search, system filter, favorites, import, detail, play, remove.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.state, this.onGo, this.initialFilter});
  final AppState state;
  final ValueChanged<String>? onGo;
  final String? initialFilter;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final searchCtrl = TextEditingController();
  final searchFocus = FocusNode();
  final pageCtrl = PageController(viewportFraction: 0.42);
  String query = '';
  String filter = 'All systems'; // All systems | Favorites | system id | core:<id>
  String view = 'flow';
  int index = 0;

  @override
  void initState() {
    super.initState();
    final layout = widget.state.settings['layout'];
    if (layout == 'grid' || layout == 'flow') view = layout as String;
    if (widget.initialFilter != null && widget.initialFilter!.isNotEmpty) {
      filter = widget.initialFilter!;
    }
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    searchFocus.dispose();
    pageCtrl.dispose();
    super.dispose();
  }

  List<GameEntry> get filtered {
    final games = widget.state.games;
    return games.where((g) {
      if (filter == 'Favorites' && !g.favorite) return false;
      if (filter != 'All systems' &&
          filter != 'Favorites' &&
          filter != 'vault') {
        if (filter.startsWith('core:')) {
          final coreId = filter.substring(5);
          if (g.coreId != coreId) {
            // Also match by compatible extension? Keep strict: coreId match
            // plus fallback — game without core assigned matches if any
            // installed core with that id opens its extension.
            final compat = widget.state.registry.catalog
                .where((m) => m.id == coreId)
                .firstOrNull;
            if (compat == null) return false;
            final exts = compat.extensions.map((e) => e.toLowerCase()).toSet();
            if (!exts.contains(g.extension.toLowerCase())) return false;
          }
        } else if (g.system != filter) {
          return false;
        }
      }
      if (query.isNotEmpty &&
          !g.title.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  List<String> get systems {
    final s = <String>{for (final g in widget.state.games) g.system};
    final out = s.toList()..sort();
    return out;
  }

  void _move(int delta) {
    final list = filtered;
    if (list.isEmpty) return;
    setState(() {
      index = (index + delta).clamp(0, list.length - 1);
    });
    if (pageCtrl.hasClients) {
      pageCtrl.animateToPage(index,
          duration: Tokens.easeDur, curve: Tokens.ease);
    }
  }

  void _openDetail(GameEntry g) {
    showGameDetail(context, gameId: g.id, state: widget.state);
  }

  void _play(GameEntry game) {
    final compatible =
        widget.state.registry.compatibleCores(game.extension);
    if (compatible.isEmpty) {
      orbitToast(context, 'No installed core opens this file yet');
      return;
    }
    final current = compatible.where((m) => m.id == game.coreId);
    final effective = current.isNotEmpty ? current.first : compatible.first;
    if (effective.id != game.coreId) {
      widget.state.setCore(game.id, effective.id);
    }
    widget.state.recordPlay(game.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(gameId: game.id, state: widget.state),
      ),
    );
  }

  void _gameMenu(GameEntry game) {
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
              leading: Icon(
                game.favorite ? Icons.star : Icons.star_outline,
                color: Tokens.text,
              ),
              title: Text(game.favorite ? 'Unfavorite' : 'Favorite',
                  style: Tokens.body()),
              onTap: () {
                widget.state.toggleFavorite(game.id);
                Navigator.of(context).pop();
                orbitToast(
                    context,
                    game.favorite
                        ? 'Removed from favorites'
                        : 'Added to your favorites');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Tokens.text),
              title: Text('Remove from library', style: Tokens.body()),
              subtitle: Text('Your file stays on disk',
                  style: Tokens.body(size: 11, color: Tokens.muted)),
              onTap: () {
                widget.state.removeGame(game.id);
                Navigator.of(context).pop();
                setState(() => index = 0);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final portrait = size.width < 700 ||
        MediaQuery.of(context).orientation == Orientation.portrait;
    final osPad = Tokens.osPad(size.width, portrait: portrait);
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final list = filtered;
        if (index >= list.length) index = list.isEmpty ? 0 : list.length - 1;
        final selected = list.isEmpty ? null : list[index];
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.slash): () {
              searchFocus.requestFocus();
            },
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (selected != null) _openDetail(selected);
            },
          },
          child: Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(osPad, 26, osPad, 0),
                  child: portrait
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScreenHeader(
                              eyebrow:
                                  'Emulation shouldn\u2019t be hard.',
                              title: 'The collection',
                              count: '${list.length} games',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OrbitSearch(
                                    controller: searchCtrl,
                                    hint: 'Find a game',
                                    onChanged: (v) => setState(
                                        () { query = v; index = 0; }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OrbitSwitcher(
                                  view: view,
                                  onView: (v) {
                                    setState(() => view = v);
                                    widget.state.setSetting('layout', v);
                                  },
                                ),
                                const SizedBox(width: 8),
                                OrbitRoundButton(
                                  icon: Icons.add,
                                  tooltip: 'Import',
                                  onPressed: () =>
                                      Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ImportScreen(
                                          state: widget.state),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : ScreenHeader(
                          eyebrow:
                              'Emulation shouldn\u2019t be hard.',
                          title: 'The collection',
                          count: '${list.length} games',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 220,
                                child: OrbitSearch(
                                  controller: searchCtrl,
                                  hint: 'Find a game',
                                  onChanged: (v) => setState(
                                      () { query = v; index = 0; }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OrbitSwitcher(
                                view: view,
                                onView: (v) {
                                  setState(() => view = v);
                                  widget.state.setSetting('layout', v);
                                },
                              ),
                              const SizedBox(width: 8),
                              OrbitRoundButton(
                                icon: Icons.add,
                                tooltip: 'Import',
                                onPressed: () =>
                                    Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ImportScreen(
                                        state: widget.state),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                _strip(osPad),
                if (list.isEmpty)
                  Expanded(child: _empty())
                else if (view == 'grid')
                  Expanded(child: _grid(list, osPad))
                else
                  Expanded(child: _flowStage(list, selected, osPad, portrait)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _strip(double osPad) {
    final dense = widget.state.settings['dense'] == true;
    final chipH = dense ? 42.0 : 50.0;
    final chips = <Widget>[
      OrbitChip(
        label: 'Time capsule',
        icon: Icons.history_outlined,
        active: false,
        height: chipH,
        onTap: () => widget.onGo?.call('vault'),
      ),
      OrbitChip(
        label: 'Favorites',
        icon: Icons.favorite_outline,
        active: filter == 'Favorites',
        height: chipH,
        onTap: () => setState(() { filter = 'Favorites'; index = 0; }),
      ),
      OrbitChip(
        label: 'All systems',
        active: filter == 'All systems',
        height: chipH,
        onTap: () => setState(() { filter = 'All systems'; index = 0; }),
      ),
      Container(
          width: 1, height: 20, color: Tokens.line, margin: const EdgeInsets.symmetric(horizontal: 8)),
      for (final s in systems)
        OrbitChip(
          label: systemLabels[s] ?? s,
          sub: s,
          active: filter == s,
          height: chipH,
          onTap: () => setState(() { filter = s; index = 0; }),
        ),
      // Per installed core shortcuts (short + id), mirrors web strip.
      for (final m in widget.state.registry.installedCores)
        OrbitChip(
          label: _shortFor(m.id),
          sub: m.id,
          active: filter == 'core:${m.id}',
          height: chipH,
          onTap: () => setState(() { filter = 'core:${m.id}'; index = 0; }),
        ),
    ];
    return Container(
      margin: EdgeInsets.fromLTRB(osPad, 0, osPad, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Tokens.line)),
      ),
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.96, 1.0],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        ),
      ),
    );
  }

  String _shortFor(String id) {
    const shorts = {
      'sameboy': 'GB', 'gambatte': 'GBC', 'mgba': 'GBA', 'mesen': 'NES',
      'snes9x': 'SNES', 'genesis_plus_gx': 'MD', 'stella': '2600',
      'dosbox_pure': 'DOS', 'beetle_pce': 'PCE', 'swanstation': 'PS',
      'mupen64plus': 'N64', 'melonds': 'DS', 'ppsspp': 'PSP',
      'flycast': 'DC', 'dolphin': 'GC', 'beetle_saturn': 'SAT',
      'fbneo': 'ARC', 'scummvm': 'ADV',
    };
    return shorts[id] ?? id.substring(0, math.min(3, id.length)).toUpperCase();
  }

  Widget _empty() {
    final hasGames = widget.state.games.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A little quiet in here.',
                style: Tokens.display(size: 22, weight: FontWeight.w500, ls: -0.5)),
            const SizedBox(height: 8),
            Text(
              hasGames
                  ? 'No titles match. Try another system or clear your search.'
                  : 'Import your own dumps to start your collection.',
              style: Tokens.body(size: 12, color: Tokens.muted, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (hasGames)
              OrbitSecondary(
                label: 'Clear filters',
                onPressed: () => setState(() {
                  filter = 'All systems';
                  query = '';
                  searchCtrl.clear();
                  index = 0;
                }),
              )
            else
              OrbitPrimary(
                label: 'Import a folder',
                icon: Icons.add,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ImportScreen(state: widget.state)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<GameEntry> list, double osPad) {
    final dense = widget.state.settings['dense'] == true;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(osPad, 25, osPad, 25),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: dense ? 120 : 160,
        mainAxisSpacing: 24,
        crossAxisSpacing: 18,
        childAspectRatio: 0.62,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final g = list[i];
        return GestureDetector(
          onTap: () => _openDetail(g),
          onLongPress: () => _gameMenu(g),
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GameCover(
                    gameId: g.id,
                    title: g.title,
                    system: systemLabels[g.system] ?? g.system,
                    radius: Tokens.radiusCover,
                  ),
                ),
                if (g.favorite)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.star,
                        size: 16, color: Tokens.accent),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _flowStage(
      List<GameEntry> list, GameEntry? selected, double osPad, bool portrait) {
    final flowH =
        (MediaQuery.of(context).size.height * 0.38).clamp(220.0, 520.0);
    // Covers scale to the available stage height so small windows
    // (and widget tests) never overflow the viewport budget.
    final coverH = (flowH - 60).clamp(140.0, 300.0);
    final coverW = coverH * 0.72;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: flowH,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Blue glow behind covers.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.5, 0.55),
                      radius: 0.6,
                      colors: [Color(0x10007BFF), Colors.transparent],
                      stops: [0.0, 0.7],
                    ),
                  ),
                ),
              ),
              PageView.builder(
                controller: pageCtrl,
                itemCount: list.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (context, i) {
                  return AnimatedBuilder(
                    animation: pageCtrl,
                    builder: (context, child) {
                      double delta = 0;
                      if (pageCtrl.position.haveDimensions) {
                        final p = pageCtrl.page ?? index.toDouble();
                        delta = (i - p).clamp(-4.0, 4.0);
                      } else {
                        delta = (i - index).toDouble().clamp(-4.0, 4.0);
                      }
                      final a = delta.abs();
                      if (a > 4) return const SizedBox.shrink();
                      final angle = (delta == 0)
                          ? 0.0
                          : (delta > 0 ? -18.0 : 18.0) * 3.14159 / 180;
                      final scale = delta == 0 ? 1.0 : (0.88 - (a - 1) * 0.06).clamp(0.6, 0.88);
                      final opacity = delta == 0 ? 1.0 : (0.87 - a * 0.13).clamp(0.23, 0.87);
                      return Opacity(
                        opacity: opacity,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)
                            ..rotateY(angle)
                            ..scaleByDouble(scale, scale, 1.0, 1.0),
                          child: GestureDetector(
                            onTap: () {
                              if (i == index) {
                                _openDetail(list[i]);
                              } else {
                                pageCtrl.animateToPage(i,
                                    duration: Tokens.easeDur, curve: Tokens.ease);
                              }
                            },
                            onLongPress: () => _gameMenu(list[i]),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GameCover(
                                  gameId: list[i].id,
                                  title: list[i].title,
                                  system: systemLabels[list[i].system] ?? list[i].system,
                                  width: coverW,
                                  height: coverH,
                                  selected: i == index,
                                  dimmed: i != index,
                                ),
                                // Reflection echo.
                                if (widget.state.settings['reflection'] != false)
                                  Opacity(
                                    opacity: 0.07,
                                    child: Transform(
                                      alignment: Alignment.topCenter,
                                      transform: Matrix4.identity()..scaleByDouble(1.0, -0.35, 1.0, 1.0),
                                      child: GameCover(
                                        gameId: list[i].id,
                                        title: list[i].title,
                                        system: '',
                                        width: coverW,
                                        height: 60,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              Positioned(
                left: osPad,
                child: _FlowBtn(
                    icon: Icons.chevron_left,
                    enabled: index > 0,
                    onTap: () => _move(-1)),
              ),
              Positioned(
                right: osPad,
                child: _FlowBtn(
                    icon: Icons.chevron_right,
                    enabled: index < list.length - 1,
                    onTap: () => _move(1)),
              ),
            ],
          ),
        ),
        Text(
          '${(index + 1).toString().padLeft(2, '0')} / ${list.length.toString().padLeft(2, '0')}',
          style: Tokens.flowCount,
        ),
        const SizedBox(height: 10),
        if (selected != null)
          Container(
            margin: EdgeInsets.fromLTRB(osPad, 0, osPad, 12),
            padding: widget.state.settings['dense'] == true
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                : const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: Tokens.dockDecor,
            child: portrait ? _dockPortrait(selected) : _dockLandscape(selected),
          ),
      ],
    );
  }

  Widget _dockLandscape(GameEntry g) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _dockCopy(g)),
        const SizedBox(width: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrbitPrimary(
                label: 'Let\u2019s play', onPressed: () => _play(g)),
            const SizedBox(width: 8),
            OrbitRoundButton(
              icon: Icons.more_horiz,
              tooltip: 'Game options and details',
              onPressed: () => _openDetail(g),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dockPortrait(GameEntry g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dockCopy(g),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OrbitPrimary(
                  label: 'Let\u2019s play',
                  expanded: true,
                  minHeight: 48,
                  onPressed: () => _play(g)),
            ),
            const SizedBox(width: 10),
            OrbitRoundButton(
              icon: Icons.more_horiz,
              tooltip: 'Game options and details',
              onPressed: () => _openDetail(g),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dockCopy(GameEntry g) {
    final base = File(g.filePath).uri.pathSegments.isEmpty
        ? ''
        : File(g.filePath).uri.pathSegments.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SystemLabel(text: systemLabels[g.system] ?? g.system),
            Container(width: 3, height: 3,
                decoration: const BoxDecoration(
                    color: Tokens.separator, shape: BoxShape.circle)),
            Text('.${g.extension}', style: Tokens.gameMeta),
            Container(width: 3, height: 3,
                decoration: const BoxDecoration(
                    color: Tokens.separator, shape: BoxShape.circle)),
            Text(_sizeLabel(g.fileSize), style: Tokens.gameMeta),
            if (g.favorite)
              const Icon(Icons.star, size: 12, color: Tokens.accent),
          ],
        ),
        const SizedBox(height: 8),
        Text(g.title, style: Tokens.dockTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(
          base.isEmpty ? 'Your dump · ready to play.' : '$base · ready to play.',
          style: Tokens.dockBodyStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return 'unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FlowBtn extends StatelessWidget {
  const _FlowBtn({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: const Color(0xC90A0A0A),
        borderRadius: BorderRadius.circular(Tokens.radiusFlowBtn),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusFlowBtn),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusFlowBtn),
              border: Border.all(color: const Color(0x30DDE6F4)),
            ),
            child: Icon(icon, size: 20, color: Tokens.text),
          ),
        ),
      ),
    );
  }
}
