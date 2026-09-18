import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cores/cheat_validators.dart';
import '../models/cheat.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';

/// Cheats keeps validate/import/export logic; chrome now matches final-01.
/// Codes apply to the live session through [onCheatsChanged] when the game
/// is running (player), and at next boot otherwise.
class CheatsScreen extends StatefulWidget {
  const CheatsScreen(
      {super.key,
      required this.gameId,
      required this.state,
      this.onCheatsChanged});
  final String gameId;
  final AppState state;
  final Future<void> Function()? onCheatsChanged;

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
          backgroundColor: Tokens.bg,
          appBar: AppBar(
            backgroundColor: Tokens.bg,
            title: Text('Cheats ($on on)',
                style:
                    Tokens.display(size: 18, weight: FontWeight.w500, ls: -0.4)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (core == null || !core.cheatsSupported)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Tokens.panel,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Tokens.line),
                  ),
                  child: Text(
                    'This core exposes no cheat hooks — codes are kept with the game and apply if you switch to a core that supports them.',
                    style: Tokens.body(size: 11, color: Tokens.accent),
                  ),
                )
              else
                Text(
                  'Families: ${core.cheatFamilies.join(', ')} — codes apply at boot, and immediately while playing.',
                  style: Tokens.body(size: 12, color: Tokens.muted),
                ),
              const SizedBox(height: 8),
              if (cheats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('No cheats yet — add one below.',
                          style: Tokens.body(
                              size: 12, color: Tokens.muted))),
                ),
              for (final cheat in cheats)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Tokens.panel,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Tokens.line),
                  ),
                  child: SwitchListTile(
                    value: cheat.enabled,
                    activeThumbColor: Tokens.accent,
                    title: Text(cheat.desc, style: Tokens.body(size: 13)),
                    subtitle: Text(
                      cheat.code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Tokens.muted,
                      ),
                    ),
                    onChanged: (_) async {
                      widget.state.toggleCheat(game.id, cheat.index);
                      await widget.onCheatsChanged?.call();
                    },
                    secondary: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: Tokens.muted),
                      onPressed: () {
                        widget.state.deleteCheat(game.id, cheat.index);
                        widget.onCheatsChanged?.call();
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OrbitPrimary(
                      label: 'Add',
                      icon: Icons.add,
                      minHeight: 46,
                      expanded: true,
                      onPressed: () =>
                          _addSheet(context, core?.cheatFamilies),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OrbitSecondary(
                      label: 'Import .cht',
                      icon: Icons.upload,
                      onPressed: () => _importSheet(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OrbitSecondary(
                      label: 'Export',
                      icon: Icons.download,
                      onPressed: () => _exportSheet(context, cheats),
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
      backgroundColor: Tokens.panel,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add cheat',
                  style: Tokens.display(
                      size: 18, weight: FontWeight.w500, ls: -0.4)),
              const SizedBox(height: 8),
              TextField(
                controller: name,
                style: Tokens.body(size: 13),
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 8),
              OrbitSelect<String>(
                value: family,
                options: (families ?? CheatValidators.families).toList(),
                onChanged: (v) {
                  if (v != null) setSheet(() => family = v);
                },
              ),
              const SizedBox(height: 8),
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
                  child: Text(error!,
                      style: Tokens.body(size: 12, color: Tokens.danger)),
                ),
              const SizedBox(height: 8),
              OrbitPrimary(
                label: 'Validate & save',
                icon: Icons.check,
                expanded: true,
                onPressed: () async {
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
                  await widget.onCheatsChanged?.call();
                  if (context.mounted) Navigator.of(context).pop();
                },
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
      backgroundColor: Tokens.panel,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Paste .cht text to import',
                style: Tokens.display(
                    size: 18, weight: FontWeight.w500, ls: -0.4)),
            const SizedBox(height: 8),
            TextField(
              controller: pasted,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            OrbitPrimary(
              label: 'Import',
              icon: Icons.upload,
              expanded: true,
              onPressed: () async {
                widget.state.importCheats(widget.gameId, pasted.text);
                await widget.onCheatsChanged?.call();
                if (context.mounted) Navigator.of(context).pop();
              },
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
      backgroundColor: Tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('.cht export (copy it somewhere safe)',
                style: Tokens.display(
                    size: 16, weight: FontWeight.w500, ls: -0.4)),
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
            OrbitPrimary(
              label: 'Copy',
              icon: Icons.copy,
              expanded: true,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
