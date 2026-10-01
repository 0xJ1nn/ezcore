import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../state/app_state.dart';
import '../state/save_sync.dart';
import '../services/system_labels.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'cheats_screen.dart';
import 'core_manager_screen.dart' show coreTitle;
import 'launch.dart';

/// One game's page: play it, resume it, load any of its saves, choose its
/// core, manage cheats, see its file — and favourite or remove it. Saves
/// live here, with their game (layout option A).
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

  Future<void> _deleteSave(SaveSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.panel,
        title: Text('Delete this save?', style: Tokens.display(size: 20)),
        content: Text(
          '${saveName(s.id)} from ${lastPlayedLabel(s.modified.millisecondsSinceEpoch)}. '
          'This cannot be undone.',
          style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Tokens.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.saves.remove(widget.gameId, s.id);
    final left = await _load();
    state.setStateCount(widget.gameId, left.length);
    if (mounted) {
      setState(() {
        _saves = Future.value(left);
      });
    }
  }

  Future<void> _remove(GameEntry g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.panel,
        title: Text('Remove ${g.title}?', style: Tokens.display(size: 20)),
        content: Text(
          'It leaves your library. The game file on your device is not '
          'deleted, and you can add it again any time.',
          style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Tokens.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
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
        return Scaffold(
          backgroundColor: Tokens.bg,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: game.favorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                icon: Icon(
                  game.favorite ? Icons.favorite : Icons.favorite_border,
                  color: game.favorite ? const Color(0xFFFF6B8B) : Tokens.text,
                ),
                onPressed: () => state.toggleFavorite(game.id),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                color: Tokens.panel,
                onSelected: (v) {
                  if (v == 'remove') _remove(game);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from library'),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: LayoutBuilder(builder: (context, c) => _body(game, c.maxWidth)),
        );
      },
    );
  }

  Widget _body(GameEntry g, double width) {
    final compact = width < 640;
    final pad = compact ? 16.0 : 32.0;
    return FutureBuilder<List<SaveSlot>>(
      future: _saves,
      builder: (context, snap) {
        final saves = snap.data ?? const <SaveSlot>[];
        final hasAuto = saves.any((s) => s.id == autoSlot);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(g, compact, hasAuto)),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section(
                          'Saves',
                          saves.isEmpty
                              ? Text(
                                  'No saves yet. Save from the pause menu while '
                                  'you play; leaving a game saves automatically.',
                                  style: Tokens.body(
                                    size: 13,
                                    color: Tokens.muted,
                                  ),
                                )
                              : SizedBox(
                                  height: 132,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: saves.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (context, i) => _SaveCard(
                                      slot: saves[i],
                                      onLoad: () => _play(g, slot: saves[i].id),
                                      onDelete: () => _deleteSave(saves[i]),
                                    ),
                                  ),
                                ),
                        ),
                        _section('Core', _corePicker(g)),
                        _section('Cheats', _cheats(g)),
                        _section('File', _file(g)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The game's own art, large and blurred, behind its cover and actions.
  Widget _hero(GameEntry g, bool compact, bool hasAuto) {
    final system = systemLabel(g.system);
    final cover = GameCover(
      gameId: g.id,
      title: g.title,
      system: shortSystemLabel(g.system),
      width: compact ? 120 : 190,
      height: compact ? 166 : 264,
    );
    final info = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          system.toUpperCase(),
          style: Tokens.body(
            size: 12,
            weight: FontWeight.w700,
            ls: 1.4,
            color: Tokens.systemLabelFg,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          g.title,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Tokens.display(
            size: compact ? 26 : 40,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            lastPlayedLabel(g.lastPlayedMs),
            if (g.stateCount > 0) countLabel(g.stateCount, 'save'),
          ].join(' · '),
          style: Tokens.body(size: 13, color: Tokens.muted),
        ),
        const SizedBox(height: 20),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrbitPrimary(
                label: hasAuto ? 'Resume' : 'Play',
                expanded: true,
                onPressed: () => _play(g, resume: hasAuto),
              ),
              if (hasAuto) ...[
                const SizedBox(height: 10),
                OrbitSecondary(
                  label: 'Play from start',
                  icon: Icons.replay,
                  onPressed: () => _play(g),
                ),
              ],
            ],
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicWidth(
                child: OrbitPrimary(
                  label: hasAuto ? 'Resume' : 'Play',
                  onPressed: () => _play(g, resume: hasAuto),
                ),
              ),
              if (hasAuto) ...[
                const SizedBox(width: 12),
                OrbitSecondary(
                  label: 'Play from start',
                  icon: Icons.replay,
                  onPressed: () => _play(g),
                ),
              ],
            ],
          ),
      ],
    );
    final pad = compact ? 16.0 : 32.0;
    // Sized by its content (cover, title, actions); the backdrop fills it.
    return Stack(
      children: [
        // Backdrop: the cover, enlarged and blurred, fading into the page.
        Positioned.fill(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Opacity(
                opacity: 0.55,
                child: Transform.scale(
                  scale: 1.3,
                  child: GameCover(
                    gameId: g.id,
                    title: '',
                    system: '',
                    radius: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66060B14), Color(0xFF060B14)],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, compact ? 56 : 88, pad, 16),
                child: compact
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [cover, const SizedBox(height: 18), info],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          cover,
                          const SizedBox(width: 32),
                          Expanded(child: info),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Tokens.display(size: 19, weight: FontWeight.w600)),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _corePicker(GameEntry g) {
    final compatible = state.registry.compatibleCores(g.extension);
    if (compatible.isEmpty) {
      return Text(
        'No installed core opens ${g.extension.toUpperCase()} files yet. '
        'Find one in Cores.',
        style: Tokens.body(size: 13, color: Tokens.muted),
      );
    }
    final current = compatible.any((m) => m.id == g.coreId)
        ? g.coreId
        : compatible.first.id;
    return Row(
      children: [
        Expanded(
          child: Text(
            compatible.length == 1
                ? 'Plays with ${compatible.first.name}.'
                : 'Choose which core plays this game. ezCORE remembers it.',
            style: Tokens.body(size: 13, color: Tokens.muted),
          ),
        ),
        const SizedBox(width: 12),
        if (compatible.length > 1)
          OrbitSelect<String>(
            value: current,
            options: [for (final m in compatible) m.id],
            labels: {
              for (final m in compatible) m.id: '${m.name} · ${coreTitle(m)}',
            },
            onChanged: (v) {
              if (v != null) state.setCore(g.id, v);
            },
          ),
      ],
    );
  }

  Widget _cheats(GameEntry g) {
    final n = state.cheatsFor(g.id).length;
    return Row(
      children: [
        Expanded(
          child: Text(
            n == 0
                ? 'No cheats added.'
                : '${countLabel(n, 'cheat')} for this game.',
            style: Tokens.body(size: 13, color: Tokens.muted),
          ),
        ),
        OrbitSecondary(
          label: 'Manage cheats',
          icon: Icons.bolt_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CheatsScreen(gameId: g.id, state: state),
            ),
          ),
        ),
      ],
    );
  }

  Widget _file(GameEntry g) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(g.filePath, style: Tokens.body(size: 13)),
      const SizedBox(height: 4),
      Text(
        '${g.extension.toUpperCase()} · ${fileSizeLabel(g.fileSize)}',
        style: Tokens.body(size: 12, color: Tokens.muted),
      ),
    ],
  );
}

/// How a save slot is named to people.
String saveName(String slot) {
  if (slot == autoSlot) return 'Automatic';
  if (slot == 'slot0') return 'Quick save';
  final m = RegExp(r'^slot-(\d{2})(\d{2})(\d{2})$').firstMatch(slot);
  if (m != null) return 'Saved ${m[1]}:${m[2]}:${m[3]}';
  return slot;
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({
    required this.slot,
    required this.onLoad,
    required this.onDelete,
  });

  final SaveSlot slot;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tokens.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                slot.id == autoSlot ? Icons.history : Icons.save_outlined,
                size: 18,
                color: Tokens.systemLabelFg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  saveName(slot.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(size: 14, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            lastPlayedLabel(slot.modified.millisecondsSinceEpoch),
            style: Tokens.body(size: 12, color: Tokens.muted),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onLoad,
                  child: const Text('Load'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Delete save',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Tokens.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
