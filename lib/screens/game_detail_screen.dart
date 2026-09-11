import 'package:flutter/material.dart';

import '../data/mock_library.dart';
import '../models/core_manifest.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'cheats_screen.dart';
import 'player_screen.dart';

class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({
    super.key,
    required this.gameId,
    required this.state,
  });
  final String gameId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final game = state.games.firstWhere((g) => g.id == gameId);
        final compatible =
            state.registry.compatibleCores(game.extension);
        final current = compatible.where((m) => m.id == game.coreId);
        final selected = current.isNotEmpty ? current.first : null;
        return Scaffold(
          appBar: AppBar(title: Text(game.title)),
          body: ListView(
            padding: const EdgeInsets.all(Tokens.pad),
            children: [
              Row(
                children: [
                  Container(
                    width: 96,
                    height: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Tokens.inkRaised,
                      borderRadius:
                          BorderRadius.circular(Tokens.radiusMd),
                      border: Border.all(color: Tokens.inkLine),
                    ),
                    child: Text(
                      game.title.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 44,
                        color: Tokens.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Chip(
                          label: Text(systemLabels[game.system] ?? game.system),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'States: ${game.stateCount} · Cheats on: ${game.cheatsOn}',
                          style: const TextStyle(color: Tokens.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Core: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      value: selected?.id,
                      hint: const Text('Pick a core'),
                      isExpanded: true,
                      items: [
                        for (final CoreManifest m in compatible)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text('${m.name} ${m.version}'),
                          ),
                      ],
                      onChanged: compatible.isEmpty
                          ? null
                          : (v) {
                              if (v != null) state.setCore(game.id, v);
                            },
                    ),
                  ),
                ],
              ),
              if (compatible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'No installed core opens this file yet — install one from Cores.',
                    style: TextStyle(color: Tokens.coin),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                              gameId: game.id,
                              state: state,
                            ),
                          ),
                        ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CheatsScreen(
                            gameId: game.id,
                            state: state,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.bolt_outlined),
                      label: Text('Cheats (${game.cheatsOn})'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.save_outlined),
                      label: Text('States (${game.stateCount})'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'File info',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${game.filePath}\n${game.fileSize} bytes · .${game.extension}',
                style: const TextStyle(color: Tokens.muted, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
