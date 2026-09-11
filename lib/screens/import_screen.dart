import 'package:flutter/material.dart';

import '../models/game_entry.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// v0 import: paste/typed folder path + mock scan preview. Real folder
/// picking (SAF on Android, picker on desktop/iOS) binds in the next pass.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final path = TextEditingController(text: '~/Games');
  bool scanned = false;

  static const _preview = [
    ('mydump2.gba', 'gba', 'mgba'),
    ('homebrew_demo.gb', 'gb', 'sameboy'),
    ('readme.txt', 'txt', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import games')),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.pad),
        children: [
          const Text(
            'Point at a folder with your own dumps. Files are hashed and matched to installed cores — nothing is uploaded anywhere.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: path,
            decoration: const InputDecoration(hintText: 'Folder path'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => setState(() => scanned = true),
            child: const Text('Scan'),
          ),
          if (scanned) ...[
            const SizedBox(height: 12),
            const Text(
              'Preview',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final (file, ext, core) in _preview)
              ListTile(
                title: Text(file),
                subtitle: Text(
                  core.isEmpty ? 'no core for .$ext' : '.$ext → $core',
                  style: TextStyle(
                    color: core.isEmpty ? Tokens.coin : Tokens.muted,
                  ),
                ),
                trailing: core.isEmpty
                    ? const Icon(Icons.warning_outlined, color: Tokens.coin)
                    : const Icon(Icons.check, color: Tokens.ok),
              ),
            FilledButton(
              onPressed: () {
                widget.state.addGame(
                  const GameEntry(
                    id: 'imported-1',
                    title: 'My Imported Dump',
                    system: 'gba',
                    filePath: '~/Games/gba/mydump2.gba',
                    extension: 'gba',
                    coreId: 'mgba',
                  ),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Import 2 games'),
            ),
          ],
        ],
      ),
    );
  }
}
