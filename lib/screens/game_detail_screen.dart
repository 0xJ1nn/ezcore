import 'package:flutter/material.dart';

import '../services/system_labels.dart';
import '../models/core_manifest.dart';
import '../state/app_state.dart';
import '../state/save_sync.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'cheats_screen.dart';
import 'player_screen.dart';

/// Shows the Orbit game-hub dialog (final-01) for [gameId].
/// Preserves all legacy detail functionality: core pick, Game→Play,
/// cheats, states, favorite, file info.
Future<void> showGameDetail(
  BuildContext context, {
  required String gameId,
  required AppState state,
}) {
  return showOrbitDialog(
    context,
    _DetailBody(gameId: gameId, state: state),
  );
}

/// Legacy route wrapper (kept for deep-link / test compat).
class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({super.key, required this.gameId, required this.state});
  final String gameId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      appBar: AppBar(backgroundColor: Tokens.bg),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 890),
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: Tokens.dialogDecor,
            child: _DetailBody(gameId: gameId, state: state),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.gameId, required this.state});
  final String gameId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final game = state.games.firstWhere((g) => g.id == gameId);
        final compatible = state.registry.compatibleCores(game.extension);
        final current = compatible.where((m) => m.id == game.coreId);
        final selected = current.isNotEmpty ? current.first : null;
        final isNarrow = MediaQuery.of(context).size.width < 640;
        final content = isNarrow
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GameCover(
                      gameId: game.id,
                      title: game.title,
                      system: systemLabels[game.system] ?? game.system,
                      width: 160,
                      height: 222,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _copy(context, game, compatible, selected),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GameCover(
                    gameId: game.id,
                    title: game.title,
                    system: systemLabels[game.system] ?? game.system,
                    width: 220,
                    height: 306,
                  ),
                  const SizedBox(width: 32),
                  Expanded(child: _copy(context, game, compatible, selected)),
                ],
              );
        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(34),
              child: content,
            ),
            Positioned(
              top: 12,
              right: 12,
              child: OrbitRoundButton(
                icon: Icons.close,
                tooltip: 'Close game details',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _copy(BuildContext context, game, List<CoreManifest> compatible,
      CoreManifest? selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${systemLabels[game.system] ?? game.system} / .${game.extension}'
              .toUpperCase(),
          style: Tokens.eyebrow,
        ),
        const SizedBox(height: 10),
        Text(game.title,
            style: Tokens.display(size: 30, weight: FontWeight.w500, ls: -0.7)),
        const SizedBox(height: 10),
        Text(
          'Your dump, ready to play. Pick a core profile, then jump in.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.7),
        ),
        const SizedBox(height: 18),
        // Core profile picker (preserved functionality).
        Row(
          children: [
            Text('Core profile', style: Tokens.body(size: 12, weight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: OrbitSelect<String?>(
                value: selected?.id,
                options: [null, for (final m in compatible) m.id],
                labels: {
                  null: compatible.isEmpty ? 'No core available' : 'Pick a core',
                  for (final m in compatible) m.id: '${m.name} ${m.version}',
                },
                onChanged: compatible.isEmpty
                    ? (_) {}
                    : (v) {
                        if (v != null) state.setCore(game.id, v);
                      },
              ),
            ),
          ],
        ),
        if (compatible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No installed core opens this file yet — install one from Systems.',
              style: Tokens.body(size: 11, color: Tokens.accent),
            ),
          ),
        const SizedBox(height: 16),
        // Specs grid (Studio / Genre slots mapped to honest local facts).
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Tokens.line)),
          ),
          padding: const EdgeInsets.only(top: 18),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.2,
            crossAxisSpacing: 20,
            children: [
              _Spec(
                  k: 'System',
                  v: systemLabels[game.system] ?? game.system),
              _Spec(k: 'Core profile', v: game.coreId.isEmpty ? '—' : game.coreId),
              _Spec(k: 'Library', v: 'Your collection'),
              _Spec(
                  k: 'Cheats',
                  v: '${game.cheatsOn} on'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OrbitPrimary(
                label: 'Let\u2019s play',
                minHeight: 52,
                onPressed: compatible.isEmpty
                    ? null
                    : () {
                        final cur = compatible
                            .where((m) => m.id == game.coreId);
                        final effective = cur.isNotEmpty
                            ? cur.first
                            : compatible.first;
                        if (effective.id != game.coreId) {
                          state.setCore(game.id, effective.id);
                        }
                        state.recordPlay(game.id);
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                                gameId: game.id, state: state),
                          ),
                        );
                      },
              ),
            ),
            const SizedBox(width: 10),
            OrbitRoundButton(
              icon: game.favorite ? Icons.star : Icons.star_outline,
              active: game.favorite,
              tooltip: 'Toggle favorite',
              onPressed: () {
                state.toggleFavorite(game.id);
                orbitToast(
                    context,
                    game.favorite
                        ? 'Removed from favorites'
                        : 'Added to your favorites');
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OrbitSecondary(
                label: 'Cheats (${game.cheatsOn})',
                icon: Icons.bolt_outlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CheatsScreen(gameId: game.id, state: state),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OrbitSecondary(
                label: 'States (${game.stateCount})',
                icon: Icons.save_outlined,
                onPressed: () => showGameSlots(context,
                    gameId: game.id, state: state),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('File info',
            style: Tokens.body(size: 12, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          '${game.filePath}\n${game.fileSize} bytes · .${game.extension}',
          style: Tokens.body(size: 12, color: Tokens.muted),
        ),
      ],
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec({required this.k, required this.v});
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(k.toUpperCase(),
            style: Tokens.body(size: 10, color: Tokens.muted)),
        const SizedBox(height: 2),
        Text(v,
            style: Tokens.display(size: 12, weight: FontWeight.w500, ls: 0),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// Snapshot slots for one game: load (resume & load into the player),
/// delete, and honest counts. Backed by the game's [SaveSyncProvider].
Future<void> showGameSlots(
  BuildContext context, {
  required String gameId,
  required AppState state,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tokens.panel,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusDialog),
      side: const BorderSide(color: Tokens.line),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scroll) => _SlotsBody(
        gameId: gameId,
        state: state,
        scroll: scroll,
      ),
    ),
  );
}

class _SlotsBody extends StatefulWidget {
  const _SlotsBody(
      {required this.gameId, required this.state, required this.scroll});
  final String gameId;
  final AppState state;
  final ScrollController scroll;

  @override
  State<_SlotsBody> createState() => _SlotsBodyState();
}

class _SlotsBodyState extends State<_SlotsBody> {
  late Future<List<SaveSlot>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.state.saves.list(widget.gameId);
  }

  void _reload() {
    setState(() {
      _future = widget.state.saves.list(widget.gameId);
    });
    _future.then((slots) =>
        widget.state.setStateCount(widget.gameId, slots.length));
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final matches =
        widget.state.games.where((g) => g.id == widget.gameId);
    if (matches.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'This game was removed from the library.',
              style:
                  Tokens.body(size: 12, color: Tokens.muted, height: 1.6),
            ),
          ),
        ),
      );
    }
    final game = matches.first;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: FutureBuilder<List<SaveSlot>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                  child:
                      CircularProgressIndicator(color: Tokens.accent));
            }
            final slots = snap.data ?? const <SaveSlot>[];
            return ListView(
              controller: widget.scroll,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Tokens.line,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Snapshots — ${slots.length}',
                    style: Tokens.display(
                        size: 22, weight: FontWeight.w500, ls: -0.5)),
                const SizedBox(height: 4),
                Text(
                  '${game.title} · snapshots live on this device',
                  style: Tokens.body(
                      size: 11, color: Tokens.muted, height: 1.6),
                ),
                const SizedBox(height: 16),
                if (slots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No snapshots yet — pause the game and choose Save a moment.',
                        textAlign: TextAlign.center,
                        style: Tokens.body(
                            size: 12, color: Tokens.muted, height: 1.6),
                      ),
                    ),
                  ),
                for (final s in slots)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Tokens.line),
                    ),
                    child: ListTile(
                      title: Text(s.id,
                          style: Tokens.body(
                              size: 13, weight: FontWeight.w600)),
                      subtitle: Text(
                        '${_fmt(s.modified)} · ${(s.size / 1024).toStringAsFixed(1)} KB',
                        style: Tokens.body(
                            size: 11, color: Tokens.muted),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Resume and load',
                            icon: const Icon(Icons.play_arrow,
                                color: Tokens.accent),
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PlayerScreen(
                                    gameId: widget.gameId,
                                    state: widget.state,
                                    initialSlot: s.id,
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete snapshot',
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: Tokens.muted),
                            onPressed: () async {
                              await widget.state.saves
                                  .remove(widget.gameId, s.id);
                              if (context.mounted) {
                                orbitToast(
                                    context, 'Snapshot deleted');
                                _reload();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
