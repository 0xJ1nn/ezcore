import 'package:flutter/material.dart';

import '../services/system_labels.dart';
import '../services/human_time.dart';
import '../state/app_state.dart';
import '../state/save_sync.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'player_screen.dart';

/// Orbit Time Capsule — save vault (final-01).
/// Lists [SaveSyncProvider] slots per game; tapping a card resumes the game.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.state});
  final AppState state;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  Future<List<_SaveRow>> _rows() async {
    final out = <_SaveRow>[];
    for (final g in widget.state.games) {
      final slots = await widget.state.saves.list(g.id);
      for (final s in slots) {
        out.add(
          _SaveRow(gameId: g.id, title: g.title, system: g.system, slot: s),
        );
      }
    }
    out.sort((a, b) => b.slot.modified.compareTo(a.slot.modified));
    return out;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final layout = Layout.of(context);
    final portrait = Layout.isPortrait(layout);
    final short = Layout.isShort(layout);
    final ultraCompact = short && size.height < 360;
    final osPad = Tokens.osPad(size.width, portrait: portrait, short_: short);
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final vaultLabel = widget.state.saves.id == 'local'
            ? 'LOCAL VAULT'
            : '${widget.state.saves.id.toUpperCase()} VAULT';
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ultraCompact) ...[
              Text('PLAY. PRESERVE. ANYWHERE.', style: Tokens.eyebrow),
              const SizedBox(height: 7),
            ],
            Text(
              'Your time capsule',
              style: Tokens.display(
                size: ultraCompact ? 20 : (short ? 22 : (portrait ? 27 : 32)),
                weight: FontWeight.w500,
                ls: -1.0,
              ),
            ),
            if (!ultraCompact) ...[
              const SizedBox(height: 8),
              Text(
                'Not just where you stopped. Where you want to return.',
                style: Tokens.body(size: 12, color: Tokens.muted, height: 1.6),
              ),
            ],
          ],
        );
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Tokens.line),
          ),
          child: Text(
            vaultLabel,
            style: Tokens.body(size: 12, ls: 0.8, color: Tokens.muted),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(osPad, short ? 10 : 26, osPad, 0),
              child: portrait
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 8), badge],
                    )
                  : Row(
                      children: [
                        Expanded(child: title),
                        badge,
                      ],
                    ),
            ),
            Expanded(
              child: FutureBuilder<List<_SaveRow>>(
                future: _rows(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: Tokens.accent),
                    );
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No moments saved yet.',
                              style: Tokens.display(size: 22),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.state.games.isEmpty
                                  ? 'Import a game, play, then save a moment from the player.'
                                  : 'Pause any game and choose “Save a moment” to pin it here.',
                              style: Tokens.body(
                                size: 12,
                                color: Tokens.muted,
                                height: 1.6,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      osPad,
                      short ? 12 : 25,
                      osPad,
                      short ? 12 : 25,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: portrait ? 400 : 320,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 23,
                      childAspectRatio: portrait ? 1.1 : 0.95,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _SaveCard(
                      row: rows[i],
                      state: widget.state,
                      onChanged: _refresh,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SaveRow {
  const _SaveRow({
    required this.gameId,
    required this.title,
    required this.system,
    required this.slot,
  });
  final String gameId;
  final String title;
  final String system;
  final SaveSlot slot;
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.row, required this.state, this.onChanged});
  final _SaveRow row;
  final AppState state;
  final VoidCallback? onChanged;

  String _fmtTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _fmtWhen(DateTime d) =>
      // Shared formatter, so vault cards and "Continue playing" tiles
      // always describe the same moment the same way.
      lastPlayedLabel(d.millisecondsSinceEpoch);

  @override
  Widget build(BuildContext context) {
    final sysLabel = systemLabels[row.system] ?? row.system;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              gameId: row.gameId,
              state: state,
              initialSlot: row.slot.id,
            ),
          ),
        );
      },
      onLongPress: () => _menu(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameCover(
                  gameId: row.gameId,
                  title: row.title,
                  system: sysLabel,
                  radius: 7,
                  dimmed: true,
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xBA0A131C),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                    ),
                    child: Text(
                      row.slot.id.toUpperCase(),
                      style: Tokens.body(size: 8, ls: 1.0, color: Tokens.text),
                    ),
                  ),
                ),
                Positioned(
                  left: 19,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.slot.id.toUpperCase(),
                        style: Tokens.body(
                          size: 9,
                          ls: 1.5,
                          color: Color(0xFFCCD8DA),
                        ),
                      ),
                      Text(
                        _fmtTime(row.slot.modified),
                        style: Tokens.display(
                          size: 24,
                          weight: FontWeight.w500,
                          ls: 0,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 17,
                  bottom: 19,
                  child: Container(
                    width: 37,
                    height: 37,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x4AFFFFFF)),
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            row.title,
            style: Tokens.display(size: 16, weight: FontWeight.w500, ls: -0.4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$sysLabel · ${_fmtWhen(row.slot.modified)} · ${_kb(row.slot.size)}',
            style: Tokens.body(size: 10, color: Tokens.muted),
          ),
        ],
      ),
    );
  }

  String _kb(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  void _menu(BuildContext context) {
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
              leading: const Icon(Icons.play_arrow, color: Tokens.text),
              title: Text('Resume and load snapshot', style: Tokens.body()),
              subtitle: Text(
                '${row.slot.id} · kept locally only',
                style: Tokens.body(size: 11, color: Tokens.muted),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      gameId: row.gameId,
                      state: state,
                      initialSlot: row.slot.id,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Tokens.text),
              title: Text('Delete snapshot', style: Tokens.body()),
              subtitle: Text(
                '${row.slot.id} · kept locally only',
                style: Tokens.body(size: 11, color: Tokens.muted),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await state.saves.remove(row.gameId, row.slot.id);
                try {
                  final remaining = await state.saves.list(row.gameId);
                  state.setStateCount(row.gameId, remaining.length);
                } catch (_) {}
                if (context.mounted) {
                  orbitToast(context, 'Snapshot deleted');
                  onChanged?.call();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
