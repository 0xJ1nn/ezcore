import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cores/cheat_validators.dart';
import '../models/cheat.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class CheatsScreen extends StatefulWidget {
  const CheatsScreen({super.key, required this.gameId, required this.state});
  final String gameId;
  final AppState state;

  @override
  State<CheatsScreen> createState() => _CheatsScreenState();
}

class _CheatsScreenState extends State<CheatsScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final game =
            widget.state.games.firstWhere((g) => g.id == widget.gameId);
        final core = widget.state.registry.catalog
            .where((m) => m.id == game.coreId)
            .firstOrNull;
        final cheats = widget.state.cheatsFor(game.id);
        final on = cheats.where((c) => c.enabled).length;
        return Scaffold(
          appBar: AppBar(title: Text('Cheats ($on on)')),
          body: ListView(
            padding: const EdgeInsets.all(Tokens.pad),
            children: [
              if (core == null || !core.cheatsSupported)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This core does not expose cheat hooks — codes are stored but cannot apply.',
                      style: TextStyle(color: Tokens.coin),
                    ),
                  ),
                )
              else
                Text(
                  'Families: ${core.cheatFamilies.join(', ')}',
                  style: const TextStyle(color: Tokens.muted, fontSize: 12),
                ),
              const SizedBox(height: 8),
              if (cheats.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No cheats yet — add one below.')),
                ),
              for (final cheat in cheats)
                SwitchListTile(
                  value: cheat.enabled,
                  title: Text(cheat.desc),
                  subtitle: Text(
                    cheat.code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Tokens.muted,
                    ),
                  ),
                  onChanged: (_) =>
                      widget.state.toggleCheat(game.id, cheat.index),
                  secondary: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () =>
                        widget.state.deleteCheat(game.id, cheat.index),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _addSheet(context, core?.cheatFamilies),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _importSheet(context),
                      icon: const Icon(Icons.upload),
                      label: const Text('Import .cht'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _exportSheet(context, cheats),
                      icon: const Icon(Icons.download),
                      label: const Text('Export'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _addSheet(BuildContext context, List<String>? families) {
    final name = TextEditingController();
    final code = TextEditingController();
    var family = (families != null && families.isNotEmpty)
        ? families.first
        : CheatValidators.families.first;
    String? error;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: Tokens.pad,
            right: Tokens.pad,
            top: Tokens.pad,
            bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.pad,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add cheat',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: name,
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: family,
                isExpanded: true,
                items: [
                  for (final f in (families ?? CheatValidators.families))
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) {
                  if (v != null) setSheet(() => family = v);
                },
              ),
              TextField(
                controller: code,
                maxLines: 4,
                decoration:
                    const InputDecoration(hintText: 'Code (one per line)'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Tokens.danger),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final problem =
                      CheatValidators.validate(family, code.text);
                  if (problem != null) {
                    setSheet(() => error = problem);
                    return;
                  }
                  final existing = widget.state.cheatsFor(widget.gameId);
                  final nextIndex = existing.isEmpty
                      ? 0
                      : existing
                              .map((c) => c.index)
                              .reduce((a, b) => a > b ? a : b) +
                          1;
                  widget.state.addCheat(
                    widget.gameId,
                    CheatEntry(
                      index: nextIndex,
                      desc: name.text.trim().isEmpty
                          ? 'Cheat $nextIndex'
                          : name.text.trim(),
                      code: code.text.trim(),
                      enabled: true,
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Validate & save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importSheet(BuildContext context) {
    final pasted = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: Tokens.pad,
          right: Tokens.pad,
          top: Tokens.pad,
          bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.pad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste .cht text to import',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pasted,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                widget.state.importCheats(widget.gameId, pasted.text);
                Navigator.of(context).pop();
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  void _exportSheet(BuildContext context, List<CheatEntry> cheats) {
    final text = serializeCht(cheats);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(Tokens.pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '.cht export (copy it somewhere safe)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
  }
}
