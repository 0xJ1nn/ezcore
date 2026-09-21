import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/content_importer.dart';
import '../services/hash_verifier.dart';
import '../services/scoped_files.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';

/// Import keeps its scan/accept logic; chrome now matches final-01.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.state});
  final AppState state;
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final path = TextEditingController();
  final _scoped = createScopedFiles();
  bool busy = false;
  String? error;
  List<ImportResult> results = [];
  String? rescanSummary;

  Future<void> scan() async {
    var input = path.text.trim();
    if (input.startsWith('~/')) {
      input = '${Platform.environment['HOME'] ?? ''}/${input.substring(2)}';
    }
    await scanPaths([input]);
  }

  /// Scans explicit files and/or directories (system picker or typed path).
  /// Directories are scanned non-recursively per the importer contract;
  /// missing paths report per-item errors instead of failing the batch.
  Future<void> scanPaths(List<String> inputs) async {
    setState(() {
      busy = true;
      error = null;
      results = [];
    });
    try {
      final importer = ContentImporter(const PlatformHashVerifier());
      final catalog = {for (final m in widget.state.registry.catalog) m.id: m};
      final known = widget.state.games.map((g) => g.sha1).toSet();
      final scanned = <ImportResult>[];
      for (var input in inputs) {
        if (input.startsWith('~/')) {
          input = '${Platform.environment['HOME'] ?? ''}/${input.substring(2)}';
        }
        if (await File(input).exists()) {
          scanned.add(await importer.importFile(
            File(input).absolute.path,
            knownShas: known,
            catalog: catalog,
          ));
        } else if (await Directory(input).exists()) {
          final scan = await importer.scanDirectory(
            Directory(input).absolute.path,
            knownShas: known,
            catalog: catalog,
          );
          if (scan.manifestError != null) throw StateError(scan.manifestError!);
          scanned.addAll(scan.results);
        } else {
          throw StateError('Directory does not exist: $input');
        }
      }
      if (mounted) setState(() => results = scanned);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> browse() async {
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      await scanPaths(files.map((f) => f.path).toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> accept() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ids = widget.state.games.map((g) => g.id).toSet();
      for (final result in results) {
        final game = result.game;
        if (game != null && ids.add(game.id)) {
          widget.state.addGame(game);
          // Remember sandboxed access for future sessions (macOS).
          await _scoped.saveBookmark(game.filePath);
        }
      }
      await widget.state.persist();
      if (mounted) {
        orbitToast(context, 'Collection updated');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Registers the typed path as a watched ROM folder (issue #14).
  /// Empty input is a user error, surfaced inline — not a toast.
  Future<void> addRomFolder() async {
    var input = path.text.trim();
    if (input.isEmpty) {
      setState(() => error = 'Enter a folder path first');
      return;
    }
    if (input.startsWith('~/')) {
      input = '${Platform.environment['HOME'] ?? ''}/${input.substring(2)}';
    }
    await widget.state.addRomFolder(input);
    if (mounted) {
      orbitToast(context, 'Folder added to watch list');
    }
  }

  /// Runs the watched-folder rescan (issue #14) and shows the report.
  Future<void> rescanFolders() async {
    setState(() {
      busy = true;
      error = null;
      rescanSummary = null;
    });
    try {
      final report = await widget.state.rescanRomFolders();
      if (mounted) {
        setState(() {
          rescanSummary = report.changed
              ? '${report.added} added · ${report.pruned} pruned · '
                  '${report.foldersScanned} folders scanned'
              : 'Library up to date · ${report.foldersScanned} folders scanned';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeRomFolder(String folder) async {
    await widget.state.removeRomFolder(folder);
  }

  @override
  void dispose() {
    path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.bg,
        appBar: AppBar(
          backgroundColor: Tokens.bg,
          title: Text('Import content',
              style: Tokens.display(size: 18, weight: FontWeight.w500, ls: -0.4)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Choose a file or folder containing your own content. Files stay on this device.',
              style: Tokens.body(size: 12, color: Tokens.muted, height: 1.7),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('import-path-field'),
              controller: path,
              enabled: !busy,
              style: Tokens.body(size: 13),
              decoration:
                  const InputDecoration(labelText: 'File or folder path'),
            ),
            const SizedBox(height: 12),
            OrbitPrimary(
              label: 'Browse files',
              icon: Icons.folder_open,
              expanded: true,
              onPressed: busy ? null : browse,
            ),
            const SizedBox(height: 8),
            OrbitPrimary(
              label: busy ? 'Working…' : 'Scan typed path',
              icon: Icons.search,
              expanded: true,
              onPressed: busy ? null : scan,
            ),
            const SizedBox(height: 8),
            OrbitSecondary(
              key: const Key('import-add-folder'),
              label: 'Add ROM folder to watch list',
              icon: Icons.folder_special_outlined,
              onPressed: busy ? null : addRomFolder,
            ),
            const SizedBox(height: 8),
            OrbitSecondary(
              key: const Key('import-rescan'),
              label: 'Re-scan ROM folders',
              icon: Icons.refresh,
              onPressed: busy ? null : rescanFolders,
            ),
            if (widget.state.romFolders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('WATCHED FOLDERS',
                  style: Tokens.body(size: 9, ls: 1.5, color: Tokens.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final folder in widget.state.romFolders)
                    InputChip(
                      label: Text(folder, style: Tokens.body(size: 11)),
                      onDeleted: busy
                          ? null
                          : () => removeRomFolder(folder),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      key: Key('remove-folder-$folder'),
                    ),
                ],
              ),
            ],
            if (rescanSummary != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(rescanSummary!,
                    style: Tokens.body(size: 12, color: Tokens.ok)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(error!,
                    style: Tokens.body(size: 12, color: Tokens.danger)),
              ),
            for (final result in results)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Tokens.line),
                  color: Tokens.panel,
                ),
                child: ListTile(
                  title: Text(
                      File(result.filePath).uri.pathSegments.last,
                      style: Tokens.body(size: 13)),
                  subtitle: Text(
                    result.error ?? result.skippedReason ?? 'Ready to import',
                    style: Tokens.body(size: 11, color: Tokens.muted),
                  ),
                  leading: Icon(
                      result.isSuccess ? Icons.check : Icons.info_outline,
                      color: result.isSuccess
                          ? Tokens.ok
                          : Tokens.muted),
                ),
              ),
            if (results.any((r) => r.isSuccess)) ...[
              const SizedBox(height: 16),
              OrbitPrimary(
                label: 'Import scanned content',
                icon: Icons.download,
                expanded: true,
                onPressed: busy ? null : accept,
              ),
            ],
          ],
        ),
      );
}
