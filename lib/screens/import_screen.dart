import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/content_importer.dart';
import '../services/hash_verifier.dart';
import '../services/scoped_files.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';

/// Import (Add games) — Orbit §8.5.
///
/// Three steps, in the design's order: pick a source, watch the scan, then
/// review what was found. The screen only presents the real importer: every
/// row, count and status comes from [ContentImporter] and the live catalog.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.state, this.scanFixture});

  final AppState state;

  /// Capture/test seam: a scripted scan so the design-parity harness can
  /// present a fixed set of outcomes. Production leaves this null and the
  /// real importer stays the only source of results.
  @visibleForTesting
  final ImportScanFixture? scanFixture;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

enum _Step { source, scan, review }

/// What the importer says about one file, in the design's four words.
enum _FileKind { ready, duplicate, noCore, notGame }

/// A scripted scan for the design-parity capture harness.
///
/// It carries no importer behaviour: the screen's state machine, review
/// ordering and accept action still run exactly as they do for a real scan.
@visibleForTesting
class ImportScanFixture {
  const ImportScanFixture({
    required this.root,
    required this.results,
    this.logPrefix,
    this.pct,
    this.hold = false,
  });

  /// Header label, e.g. `~/Games` or `SD-CARD/Games`.
  final String root;

  /// Overrides the mono log's path prefix, e.g. `SD-CARD/Games`.
  final String? logPrefix;

  final List<ImportResult> results;

  /// Fixed progress (0–1) for captures; null animates like a real scan.
  final double? pct;

  /// Keeps the screen on Scan (a long scan) instead of advancing to Review.
  final bool hold;
}

class _ImportScreenState extends State<ImportScreen>
    with TickerProviderStateMixin {
  final path = TextEditingController();
  final _scoped = createScopedFiles();

  bool busy = false;
  String? error;
  List<ImportResult> results = [];

  /// Scanned results waiting for the progress animation to finish.
  List<ImportResult> _pending = [];
  String? _scanError;
  bool _scanDone = false;

  String? rescanSummary;
  String? folderNote;

  _Step _step = _Step.source;

  /// Folder/file the current scan started from, for the "Scanning …" line
  /// and the relative paths in the mono log.
  String? _scanRoot;
  List<String> _scanInputs = [];

  /// Bumped on every scan/stop so a stale callback cannot land.
  int _generation = 0;

  /// Scripted-scan display state (capture harness only; null in production).
  double? _fixturePct;
  bool _fixtureHold = false;

  bool _advancedOpen = false;

  /// The source card showing the focus halo. One at a time, like every
  /// other surface in the shell.
  int _focusedSource = 0;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onProgressStatus);
  }

  @override
  void dispose() {
    _progress.removeStatusListener(_onProgressStatus);
    _sweep.dispose();
    _progress.dispose();
    path.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Source card actions
  // ---------------------------------------------------------------------

  /// The watched folder the first card points at, if there is one.
  String? get _watchedFolder {
    if (state.romFolders.isNotEmpty) return state.romFolders.first;
    final roots = ContentImporter.driveRoots();
    return roots.isEmpty ? null : roots.first;
  }

  void _scanWatched() {
    final folder = _watchedFolder;
    if (folder == null) {
      _pickFolder();
    } else {
      _startScan([folder]);
    }
  }

  Future<void> _pickFolder() async {
    try {
      final dir = await getDirectoryPath();
      if (dir == null || dir.isEmpty) return;
      await _startScan([dir]);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _pickRemovable() async {
    final roots = ContentImporter.driveRoots();
    if (roots.isEmpty) {
      setState(() => error =
          'No removable drive connected. Choose a folder instead.');
      return;
    }
    await _startScan(roots);
  }

  // ---------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------

  /// Scans explicit files and/or directories (system picker or typed path).
  /// Directories are scanned non-recursively per the importer contract;
  /// missing paths report per-item errors instead of failing the batch.
  Future<void> _startScan(List<String> inputs) async {
    if (busy) return;
    final fixture = widget.scanFixture;
    if (fixture == null &&
        (inputs.isEmpty || inputs.every((i) => i.trim().isEmpty))) {
      setState(() => error = 'Enter a folder path first');
      return;
    }
    final generation = ++_generation;
    final normalized = fixture != null
        ? inputs
        : [
            for (final i in inputs)
              if (i.trim().isNotEmpty)
                i.startsWith('~/')
                    ? '${Platform.environment['HOME'] ?? ''}/${i.substring(2)}'
                    : i,
          ];
    setState(() {
      busy = true;
      error = null;
      _scanError = null;
      _scanDone = false;
      _pending = [];
      results = [];
      _step = _Step.scan;
      _scanInputs = normalized;
      _scanRoot = fixture?.root ??
          (normalized.length == 1 ? _prettyPath(normalized.first) : null);
      _fixturePct = fixture?.pct;
      _fixtureHold = fixture?.hold ?? false;
    });
    _sweep.repeat();

    if (fixture != null) {
      // Scripted scan: the outcomes are known up front. A held fixture keeps
      // the sweep on screen (a long scan); otherwise the normal wait for the
      // progress bar still applies.
      _pending = fixture.results;
      _scanDone = !fixture.hold;
      if (fixture.pct == null) _progress.forward(from: 0);
      _maybeLeaveScan();
      return;
    }

    _progress.forward(from: 0);

    List<ImportResult>? scanned;
    Object? failure;
    try {
      scanned = await _runScan(normalized);
    } catch (e) {
      failure = e;
    }
    if (!mounted || generation != _generation) return;
    _pending = scanned ?? [];
    _scanError = failure?.toString();
    _scanDone = true;
    _maybeLeaveScan();
  }

  Future<List<ImportResult>> _runScan(List<String> inputs) async {
    final importer = ContentImporter(const PlatformHashVerifier());
    final catalog = {for (final m in state.registry.catalog) m.id: m};
    final known = state.games.map((g) => g.sha1).toSet();
    final scanned = <ImportResult>[];
    // When the managed folder exists, copy picked files into it so every
    // game lands in one place. Directories and missing paths pass through
    // untouched: folders scan in place, missing paths keep their errors.
    var toScan = inputs;
    if (state.ezcoreRomsFolder != null) {
      toScan = await state.copyGamesIntoRomsFolder(inputs);
    }
    for (final input in toScan) {
      if (await File(input).exists()) {
        scanned.add(
          await importer.importFile(
            File(input).absolute.path,
            knownShas: known,
            catalog: catalog,
          ),
        );
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
    // Stable order regardless of how the filesystem listed the directory.
    scanned.sort(
      (a, b) => a.filePath
          .toLowerCase()
          .compareTo(b.filePath.toLowerCase()),
    );
    return scanned;
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _maybeLeaveScan();
  }

  /// Waits for both the real scan and the minimum visible sweep, so a fast
  /// folder still reads as a scan instead of a flash.
  void _maybeLeaveScan() {
    if (!mounted || _step != _Step.scan) return;
    if (_fixtureHold) return;
    if (!_scanDone || !_progress.isCompleted) return;
    final failure = _scanError;
    if (failure != null) {
      setState(() {
        busy = false;
        _step = _Step.source;
        error = failure;
        results = [];
      });
      _stopAnimation();
      return;
    }
    setState(() {
      busy = false;
      results = _pending;
      _step = _Step.review;
    });
    _stopAnimation();
  }

  void _stopAnimation() {
    _sweep.stop();
    _progress.stop();
  }

  void _stopScan() {
    _generation++;
    _stopAnimation();
    setState(() {
      busy = false;
      _scanDone = true;
      _step = _Step.source;
      results = [];
    });
    if (mounted) orbitToast(context, 'Scan stopped. Nothing was added.');
  }

  // ---------------------------------------------------------------------
  // Existing importer actions (kept; presented in the advanced panel)
  // ---------------------------------------------------------------------

  Future<void> browse() async {
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      await _startScan(files.map((f) => f.path).toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> scanTypedPath() async => _startScan([path.text.trim()]);

  /// Registers the typed path as a watched ROM folder (issue #14).
  Future<void> addRomFolder() async {
    var input = path.text.trim();
    if (input.isEmpty) {
      setState(() => error = 'Enter a folder path first');
      return;
    }
    if (input.startsWith('~/')) {
      input = '${Platform.environment['HOME'] ?? ''}/${input.substring(2)}';
    }
    await state.addRomFolder(input);
    if (mounted) {
      setState(() {});
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
      final report = await state.rescanRomFolders();
      if (mounted) {
        setState(() {
          rescanSummary = report.changed
              ? '${report.added} added · ${report.pruned} pruned · '
                  '${report.relabeled} fixed · '
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
    await state.removeRomFolder(folder);
    if (mounted) setState(() {});
  }

  Future<void> accept() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ids = state.games.map((g) => g.id).toSet();
      var added = 0;
      for (final result in results) {
        if (_kindOf(result) != _FileKind.ready) continue;
        final game = result.game;
        if (game != null && ids.add(game.id)) {
          state.addGame(game);
          added++;
          // Remember sandboxed access for future sessions (macOS).
          await _scoped.saveBookmark(game.filePath);
        }
      }
      await state.persist();
      if (mounted) {
        orbitToast(
          context,
          added == 1 ? 'Added 1 game' : 'Added $added games',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Confirms and creates the managed "ezCORE ROMs" folder.
  ///
  /// The design has no dialog on open, so the first source card carries the
  /// offer inline; this confirmation only appears after the user picks it.
  Future<void> _offerRomsFolder() async {
    if (busy) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'One place for your games?',
          style: Tokens.body(size: 15, weight: FontWeight.w600),
        ),
        content: Text(
          'Shall ezCORE create an "ezCORE ROMs" folder on your device '
          'and copy all the ROMs there?',
          style: Tokens.body(size: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            key: const Key('roms-folder-later'),
            onPressed: () => Navigator.of(ctx).pop('later'),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('roms-folder-create'),
            onPressed: () => Navigator.of(ctx).pop('create'),
            child: const Text('Create folder'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'create') {
      final dir = await state.createEzcoreRomsFolder();
      if (!mounted) return;
      setState(() {
        folderNote = 'ezCORE ROMs folder created — copies land in $dir';
      });
    } else {
      await state.declineEzcoreRomsFolder();
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------
  // Classification
  // ---------------------------------------------------------------------

  _FileKind _kindOf(ImportResult r) {
    final game = r.game;
    if (game != null) {
      if (game.coreId.isNotEmpty && !state.registry.isInstalled(game.coreId)) {
        return _FileKind.noCore;
      }
      return _FileKind.ready;
    }
    final reason = (r.skippedReason ?? r.error ?? '').toLowerCase();
    if (reason.contains('duplicate')) return _FileKind.duplicate;
    return _FileKind.notGame;
  }

  /// Review order: everything that will be added first, then duplicates,
  /// then the ones that need a system — the design's row order. Scan order
  /// is preserved inside each group.
  List<ImportResult> get _reviewable {
    final ready = <ImportResult>[];
    final duplicate = <ImportResult>[];
    final skipped = <ImportResult>[];
    for (final r in results) {
      switch (_kindOf(r)) {
        case _FileKind.ready:
          ready.add(r);
        case _FileKind.duplicate:
          duplicate.add(r);
        case _FileKind.noCore:
          skipped.add(r);
        case _FileKind.notGame:
          break;
      }
    }
    return [...ready, ...duplicate, ...skipped];
  }

  int get _readyCount =>
      results.where((r) => _kindOf(r) == _FileKind.ready).length;

  /// The system for a row: the game's own when the importer built one, else
  /// the first catalog core claiming the file's extension (a duplicate is
  /// still a Game Boy Advance file).
  String _systemOf(ImportResult r) {
    final game = r.game;
    if (game != null) return game.system;
    final ext = r.filePath.split('.').last.toLowerCase();
    for (final m in state.registry.catalog) {
      if (m.extensions.any((e) => e.toLowerCase() == ext)) {
        return m.systems.isNotEmpty ? m.systems.first : ext;
      }
    }
    return ext;
  }

  int _sizeOf(ImportResult r) {
    final game = r.game;
    if (game != null && game.fileSize > 0) return game.fileSize;
    try {
      return File(r.filePath).lengthSync();
    } catch (_) {
      return game?.fileSize ?? 0;
    }
  }

  // ---------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final layout = Layout.ofSize(media.size, media.orientation);
    final phonePortrait = layout == OrbitLayout.phonePortrait;
    final phoneLandscape = layout == OrbitLayout.phoneLandscape;
    final phone = Layout.isPhone(layout);
    final hasRail = Layout.hasRail(layout);

    // The design's content origin: the body sits 44 from the rail (48 on the
    // phone), the header 48. Only the desktop/tablet families carry the
    // 4 px header shift; phone families align both edges.
    final double rail =
        hasRail ? (phoneLandscape ? Tokens.railShort : Tokens.rail) : 0.0;
    final double bodySide = phonePortrait ? 24.0 : (phoneLandscape ? 26.0 : 44.0);
    final double headerInset = phone ? 0.0 : 4.0;
    final double rightSide = phonePortrait ? 24.0 : (phoneLandscape ? 26.0 : 48.0);
    final double headerTop =
        phonePortrait ? 53.0 : (phoneLandscape ? 26.0 : 88.0);
    final double headerGap =
        phonePortrait ? 48.0 : (phoneLandscape ? 22.0 : 31.0);
    final double titleSize = phone ? 30.0 : 44.0;
    final double eyebrowSize = phone ? 12.0 : 13.0;
    final double bottomPad = phonePortrait ? 49.0 : 24.0;

    return Scaffold(
      backgroundColor: Tokens.bg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_step == _Step.scan) {
              _stopScan();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        },
        child: LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth - rail - bodySide - rightSide;
            final headerExtent = eyebrowSize + 8 + titleSize;
            final bodyTop = headerTop + headerExtent + headerGap;
            final viewportBody = math.max(0.0, c.maxHeight - bodyTop - bottomPad);
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: headerInset),
                  child: _header(
                    phone: phone,
                    phoneLandscape: phoneLandscape,
                    titleSize: titleSize,
                    eyebrowSize: eyebrowSize,
                    showPills: !phonePortrait,
                  ),
                ),
                SizedBox(height: headerGap),
                switch (_step) {
                  _Step.source => _sourceBody(width, phone),
                  _Step.scan => _scanBody(width, viewportBody),
                  _Step.review => _reviewBody(width),
                },
              ],
            );
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                rail + bodySide,
                headerTop,
                rightSide,
                bottomPad,
              ),
              child: content,
            );
          },
        ),
      ),
    );
  }

  Widget _header({
    required bool phone,
    required bool phoneLandscape,
    required double titleSize,
    required double eyebrowSize,
    required bool showPills,
  }) {
    final (eyebrow, title) = switch (_step) {
      _Step.source => ('POINT AT A FOLDER', 'Add games'),
      _Step.scan => ('MATCHING BY CONTENTS', 'Looking for games…'),
      _Step.review => (
        'NOTHING CHANGES UNTIL YOU SAY',
        'Here’s what I found',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.display(
                  size: eyebrowSize,
                  weight: FontWeight.w500,
                  ls: (phone ? 0.28 : 0.30) * eyebrowSize,
                  color: Tokens.muted,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.display(
                  size: titleSize,
                  weight: FontWeight.w600,
                  ls: -0.03 * titleSize,
                  height: 1,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (showPills) ...[
          const SizedBox(width: 16),
          Padding(
            padding: EdgeInsets.only(top: phoneLandscape ? 4 : 16),
            child: _StepPills(step: _step, onSelect: _selectStep),
          ),
        ],
      ],
    );
  }

  void _selectStep(_Step step) {
    if (step == _step) return;
    switch (step) {
      case _Step.source:
        setState(() => _step = _Step.source);
      case _Step.scan:
        if (_step == _Step.source) {
          _scanWatched();
        } else if (_step == _Step.review) {
          setState(() {
            results = [];
            _step = _Step.source;
          });
        }
      case _Step.review:
        if (results.isNotEmpty) {
          setState(() => _step = _Step.review);
        }
    }
  }

  // -- Source ------------------------------------------------------------

  Widget _sourceBody(double width, bool phone) {
    final watched = _watchedFolder;
    final hasWatched = watched != null && watched.isNotEmpty;
    final cards = Column(
      children: [
        _SourceCard(
          key: const Key('import-source-watched'),
          icon: hasWatched ? Symbols.folderSpecial : Symbols.createNewFolder,
          title: hasWatched ? _watchedTitle : 'Create an ezCORE ROMs folder',
          description: hasWatched
              ? _watchedDescription
              : 'One place for your games on this device',
          focused: _focusedSource == 0,
          onFocus: () => setState(() => _focusedSource = 0),
          phone: phone,
          onTap: busy ? null : (hasWatched ? _scanWatched : _offerRomsFolder),
        ),
        const SizedBox(height: 12),
        _SourceCard(
          key: const Key('import-source-folder'),
          icon: Symbols.createNewFolder,
          title: 'Choose another folder…',
          description: 'Browse this device with your controller',
          focused: _focusedSource == 1,
          onFocus: () => setState(() => _focusedSource = 1),
          phone: phone,
          onTap: busy ? null : _pickFolder,
        ),
        const SizedBox(height: 12),
        _SourceCard(
          key: const Key('import-source-drive'),
          icon: Symbols.usb,
          title: 'Removable drive',
          description: _driveDescription,
          focused: _focusedSource == 2,
          onFocus: () => setState(() => _focusedSource = 2),
          phone: phone,
          onTap: busy ? null : _pickRemovable,
        ),
      ],
    );
    final privacy = _PrivacyPanel(phone: phone);
    final wide = !phone && width >= 1200;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: cards,
                ),
              ),
              const SizedBox(width: 40),
              SizedBox(width: 440, child: privacy),
            ],
          )
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: cards,
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: privacy,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 18),
          Text(
            error!,
            style: Tokens.body(size: 14, color: Tokens.dangerText),
          ),
        ],
        if (folderNote != null) ...[
          const SizedBox(height: 18),
          Text(folderNote!, style: Tokens.body(size: 14, color: Tokens.ok)),
        ],
        // The design's Source step carries no power-user row; keep the
        // path/watched-folder actions reachable by scrolling on wide
        // screens, and inline where the viewport is already tight.
        SizedBox(height: phone ? 18 : 440),
        Align(
          alignment: Alignment.centerLeft,
          child: _AdvancedScan(
            open: _advancedOpen,
            busy: busy,
            path: path,
            onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
            onBrowse: browse,
            onScanPath: scanTypedPath,
            onAddFolder: addRomFolder,
            onRescan: rescanFolders,
            folders: state.romFolders,
            onRemoveFolder: removeRomFolder,
            rescanSummary: rescanSummary,
          ),
        ),
      ],
    );
  }

  String get _watchedTitle {
    final folder = _watchedFolder;
    if (folder == null) return 'Choose a folder…';
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty && folder.startsWith(home)) {
      return '~${folder.substring(home.length)}';
    }
    return folder.split(Platform.pathSeparator).last;
  }

  String get _watchedDescription {
    if (_watchedFolder == null) return 'Pick where your games live';
    final n = state.games.length;
    return 'Watched · ${n == 1 ? '1 game' : '$n games'} · '
        'checked when ezCORE opens';
  }

  String get _driveDescription {
    final roots = ContentImporter.driveRoots();
    if (roots.isEmpty) return 'No removable drive connected';
    return 'Look for games on a card or drive you’ve plugged in';
  }

  // -- Scan --------------------------------------------------------------

  Widget _scanBody(double width, double viewportBody) {
    final layout = Layout.ofSize(MediaQuery.sizeOf(context),
        MediaQuery.orientationOf(context));
    final phonePortrait = layout == OrbitLayout.phonePortrait;
    final phoneLandscape = layout == OrbitLayout.phoneLandscape;
    return AnimatedBuilder(
      animation: Listenable.merge([_sweep, _progress]),
      builder: (context, _) {
        final pct =
            _fixturePct ?? (_progress.isCompleted ? 1.0 : _progress.value * 0.96);
        final done = _pending;
        final found = done
            .where((r) => _kindOf(r) != _FileKind.notGame)
            .length;
        final radarSize = phonePortrait
            ? math.min(300.0, width)
            : (phoneLandscape ? 260.0 : math.min(440.0, width));
        final radar = _Radar(
          size: radarSize,
          phone: phonePortrait,
          pct: pct,
          spin: _sweep.value,
          found: found,
        );
        final progress = _ScanProgress(
          root: _scanRoot,
          pct: pct,
          results: done,
          logPath: _logPath,
          kindOf: _kindOf,
          phone: phonePortrait,
          landscape: phoneLandscape,
        );
        if (phonePortrait) {
          return SizedBox(
            height: math.max(viewportBody, radarSize + 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: radar),
                const SizedBox(height: 42),
                progress,
                const Spacer(),
                _StopScanButton(onTap: _stopScan),
              ],
            ),
          );
        }
        if (phoneLandscape) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  radar,
                  const SizedBox(width: 26),
                  Expanded(child: progress),
                ],
              ),
              const SizedBox(height: 16),
              _StopScanButton(onTap: _stopScan),
            ],
          );
        }
        if (width < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: radar,
              )),
              const SizedBox(height: 34),
              progress,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: radar,
            ),
            const SizedBox(width: 76),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: progress,
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Games/NDS/paper_lunar.nds": the scanned folder and the file inside it.
  String _logPath(ImportResult r) {
    final fixture = widget.scanFixture;
    if (fixture != null) {
      // Scripted results already carry the display path.
      final prefix = fixture.logPrefix;
      if (prefix == null) return r.filePath;
      final p = r.filePath;
      return p.startsWith('Games/') ? '$prefix/${p.substring(6)}' : p;
    }
    for (final root in _scanInputs) {
      if (r.filePath == root) return root.split(Platform.pathSeparator).last;
      final prefix = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      if (r.filePath.startsWith(prefix)) {
        final base = root.split(Platform.pathSeparator).last;
        return '$base/${r.filePath.substring(prefix.length).replaceAll(Platform.pathSeparator, '/')}';
      }
    }
    return r.filePath.split(Platform.pathSeparator).last;
  }

  String _prettyPath(String p) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty && p.startsWith(home)) {
      return '~${p.substring(home.length)}';
    }
    final parts = p.split(Platform.pathSeparator);
    return parts.isEmpty || parts.last.isEmpty ? p : parts.last;
  }

  // -- Review ------------------------------------------------------------

  Widget _reviewBody(double width) {
    final layout = Layout.ofSize(MediaQuery.sizeOf(context),
        MediaQuery.orientationOf(context));
    final phone = Layout.isPhone(layout);
    final compact = !phone && width < 900;
    final list = _ReviewList(
      results: _reviewable,
      kindOf: _kindOf,
      systemOf: _systemOf,
      sizeOf: _sizeOf,
      phone: phone,
    );
    final summary = _ReviewSummary(
      ready: _readyCount,
      duplicate: results
          .where((r) => _kindOf(r) == _FileKind.duplicate)
          .length,
      noCore: results.where((r) => _kindOf(r) == _FileKind.noCore).length,
      showGlyph: !phone,
      compact: phone || compact,
      busy: busy,
      onAdd: accept,
      onBack: () => setState(() {
        results = [];
        _step = _Step.source;
      }),
    );
    if (phone || compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          const SizedBox(height: 20),
          list,
        ],
      );
    }
    // The design's two columns: an 820 px list, a 440 px summary pinned to
    // the right edge of the same content width.
    final listWidth = math.min(820.0, math.max(360.0, width - 424));
    return SizedBox(
      height: math.max(92.0, _reviewable.length * 92.0),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: listWidth,
            child: list,
          ),
          Positioned(
            right: 0,
            top: 0,
            width: 440,
            child: summary,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header pieces
// ---------------------------------------------------------------------------

class _StepPills extends StatelessWidget {
  const _StepPills({required this.step, required this.onSelect});

  final _Step step;
  final ValueChanged<_Step> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = ['Choose', 'Scan', 'Review'];
    final current = _Step.values.indexOf(step);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _StepPill(
            key: Key('import-step-${_Step.values[i].name}'),
            number: '${i + 1}',
            label: labels[i],
            active: i == current,
            passed: i <= current,
            onTap: () => onSelect(_Step.values[i]),
          ),
        ],
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    super.key,
    required this.number,
    required this.label,
    required this.active,
    required this.passed,
    required this.onTap,
  });

  final String number;
  final String label;
  final bool active;
  final bool passed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = passed ? Colors.white : Tokens.separator;
    return Semantics(
      button: true,
      selected: active,
      label: '$number $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: active ? const Color(0x33007BFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1FDDE6F4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  number,
                  style: Tokens.display(
                    size: 12,
                    weight: FontWeight.w700,
                    ls: 0,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Tokens.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: fg,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source
// ---------------------------------------------------------------------------

class _SourceCard extends StatefulWidget {
  const _SourceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.focused,
    required this.onFocus,
    this.phone = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool focused;
  final VoidCallback onFocus;
  final bool phone;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.focused || _focus || _hover;
    final height = widget.phone ? 84.0 : 92.0;
    final tile = widget.phone ? 46.0 : 52.0;
    return Semantics(
      button: true,
      label: widget.title,
      hint: widget.description,
      child: FocusableActionDetector(
        autofocus: widget.focused,
        onShowFocusHighlight: (v) {
          setState(() => _focus = v);
          if (v) widget.onFocus();
        },
        onShowHoverHighlight: (v) {
          setState(() => _hover = v);
          if (v) widget.onFocus();
        },
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: Tokens.fastDur,
            curve: Tokens.ease,
            height: height,
            transform: Matrix4.translationValues(active ? 6 : 0, 0, 0),
            padding: EdgeInsets.symmetric(horizontal: widget.phone ? 18 : 24),
            decoration: BoxDecoration(
              // Opaque surfaces: the focus halo is painted as a shadow behind
              // the card, and Flutter (unlike CSS) does not clip an outer
              // shadow to the border box, so a translucent fill would let the
              // blue glow show through. These are the design's fills composited
              // over the backdrop.
              color: active
                  ? const Color(0xFF1D2434)
                  : const Color(0xFF0E141D),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? const Color(0x24DDE6F4)
                    : const Color(0x1FDDE6F4),
              ),
              boxShadow: active ? Tokens.halo : null,
            ),
            child: Row(
              children: [
                Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: const Color(0x1F007BFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.phone ? 24 : 28,
                    color: Tokens.iconBlue,
                  ),
                ),
                SizedBox(width: widget.phone ? 14 : 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: widget.phone ? 16 : 18,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: widget.phone ? 13 : 14,
                          color: Tokens.muted,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Symbols.chevronRight,
                  size: 24,
                  color: Tokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel({required this.phone});

  final bool phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(phone ? 22 : 28),
      decoration: BoxDecoration(
        color: const Color(0x73060A11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1FDDE6F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.shieldLock, size: 30, color: Tokens.iconBlue),
          const SizedBox(height: 14),
          Text(
            'Reads files on this device. Nothing leaves it.',
            style: Tokens.display(
              size: phone ? 18 : 20,
              weight: FontWeight.w600,
              ls: 0,
              height: 1.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'ezCORE ships no games, BIOS files or keys. Add the ones you '
            'own. Scanning matches files by their contents, so names and '
            'folders don’t matter.',
            style: Tokens.body(
              size: phone ? 14 : 15,
              height: 1.6,
              color: Tokens.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan
// ---------------------------------------------------------------------------

class _Radar extends StatelessWidget {
  const _Radar({
    required this.size,
    required this.phone,
    required this.pct,
    required this.spin,
    required this.found,
  });

  final double size;
  final bool phone;
  final double pct;
  final double spin;
  final int found;

  /// The design's blips: (x, y, colour, threshold in percent).
  static const _blips = [
    (90.0, 120.0, 0xFF7DE89A, 10.0),
    (300.0, 90.0, 0xFF7DE89A, 25.0),
    (340.0, 300.0, 0xFF9AA8BC, 40.0),
    (120.0, 330.0, 0xFFFFC46B, 55.0),
    (220.0, 60.0, 0xFF7DE89A, 70.0),
    (60.0, 240.0, 0xFF7DE89A, 85.0),
  ];

  /// Phone-frame blips (Devices 3e), in the same 440-box units.
  static const _phoneBlips = [
    (87.0, 117.0, 0xFF7DE89A, 10.0),
    (307.0, 87.0, 0xFF7DE89A, 30.0),
    (131.0, 322.0, 0xFFFFC46B, 55.0),
  ];

  @override
  Widget build(BuildContext context) {
    final scale = size / 440;
    final blips = phone ? _phoneBlips : _blips;
    final dot = phone ? 9.0 : 10.0;
    final rings = phone ? const [66.0] : const [60.0, 130.0];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x403B8BFF)),
              ),
            ),
          ),
          for (final inset in rings)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(inset * scale),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: inset == rings.first
                          ? const Color(0x2E3B8BFF)
                          : const Color(0x243B8BFF),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: ClipOval(
              child: Transform.rotate(
                angle: spin * 2 * math.pi,
                child: CustomPaint(painter: _SweepPainter()),
              ),
            ),
          ),
          for (final (x, y, colour, threshold) in blips)
            if (pct * 100 >= threshold)
              Positioned(
                left: x * scale,
                top: y * scale,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(colour),
                    boxShadow: [
                      BoxShadow(color: Color(colour), blurRadius: 14),
                    ],
                  ),
                ),
              ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$found',
                  style: Tokens.display(
                    size: phone ? 60 : 72,
                    weight: FontWeight.w700,
                    ls: -0.04 * 72,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'games found',
                  style: Tokens.body(
                    size: 14,
                    weight: FontWeight.w600,
                    color: Tokens.muted,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The rotating radar sweep: a 60° sector fading from clear to electric
/// blue, as the design's conic gradient.
class _SweepPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    canvas.save();
    canvas.translate(radius, radius);
    canvas.rotate(-math.pi / 2);
    final path = Path()
      ..moveTo(0, 0)
      ..arcTo(Rect.fromCircle(center: Offset.zero, radius: radius),
          0, math.pi / 3, false)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const SweepGradient(
          colors: [Color(0x00007BFF), Color(0x80007BFF)],
          stops: [0, 1],
          startAngle: 0,
          endAngle: math.pi / 3,
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepPainter oldDelegate) => false;
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress({
    required this.root,
    required this.pct,
    required this.results,
    required this.logPath,
    required this.kindOf,
    required this.phone,
    required this.landscape,
  });

  final String? root;
  final double pct;
  final List<ImportResult> results;
  final String Function(ImportResult) logPath;
  final _FileKind Function(ImportResult) kindOf;
  final bool phone;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final pctText = '${(pct * 100).round()}%';
    final maxRows = phone ? 4 : 6;
    final rows = results.length > maxRows
        ? results.sublist(results.length - maxRows)
        : results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Scanning ${root ?? 'your files'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.body(
                  size: phone ? 14 : (landscape ? 14 : 15),
                  weight: FontWeight.w600,
                  height: 1,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              pctText,
              style: Tokens.body(
                size: phone ? 14 : 15,
                weight: FontWeight.w600,
                height: 1,
                color: Tokens.muted,
              ),
            ),
          ],
        ),
        SizedBox(height: phone ? 10 : 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0x14DDE6F4)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct.clamp(0, 1),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Tokens.accentDeep, Tokens.iconBlue],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Tokens.accent,
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: phone ? 22 : 26),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Opacity(
              opacity: (i + 1) / rows.length,
              child: _FileLogRow(
                path: logPath(rows[i]),
                kind: kindOf(rows[i]),
                phone: phone || landscape,
              ),
            ),
          ),
      ],
    );
  }
}

class _FileLogRow extends StatelessWidget {
  const _FileLogRow({
    required this.path,
    required this.kind,
    required this.phone,
  });

  final String path;
  final _FileKind kind;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (kind) {
      _FileKind.ready => ('New', Tokens.ok),
      _FileKind.duplicate => ('Already in collection', Tokens.muted),
      _FileKind.noCore => (phone ? 'No core' : 'No system installed', Tokens.warn),
      _FileKind.notGame => ('Not a game', Tokens.separator),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.mono(
              size: phone ? 12 : 13,
              color: Tokens.muted,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: Tokens.mono(
            size: phone ? 12 : 13,
            color: colour,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _StopScanButton extends StatelessWidget {
  const _StopScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            alignment: Alignment.center,
            decoration: Tokens.secondaryButton(),
            child: Text(
              'Stop scan',
              style: Tokens.body(
                size: 15,
                weight: FontWeight.w700,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review
// ---------------------------------------------------------------------------

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.results,
    required this.kindOf,
    required this.systemOf,
    required this.sizeOf,
    required this.phone,
  });

  final List<ImportResult> results;
  final _FileKind Function(ImportResult) kindOf;
  final String Function(ImportResult) systemOf;
  final int Function(ImportResult) sizeOf;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x73060A11),
          border: Border.all(color: const Color(0x1FDDE6F4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < results.length; i++)
              _ReviewRow(
                result: results[i],
                kind: kindOf(results[i]),
                system: systemOf(results[i]),
                bytes: sizeOf(results[i]),
                phone: phone,
                last: i == results.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.result,
    required this.kind,
    required this.system,
    required this.bytes,
    required this.phone,
    required this.last,
  });

  final ImportResult result;
  final _FileKind kind;
  final String system;
  final int bytes;
  final bool phone;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final title = kind == _FileKind.noCore || kind == _FileKind.notGame
        ? _fileName(result.filePath)
        : _prettyName(result.filePath);
    final subtitle = switch (kind) {
      _FileKind.ready => '${systemLabel(system)} · ${_size(bytes)}',
      _FileKind.duplicate =>
        '${systemLabel(system)} · same file as one you have',
      _FileKind.noCore => '${systemLabel(system)} · no core installed for this system',
      _FileKind.notGame => result.skippedReason ?? result.error ?? 'Not a game',
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: phone ? 16 : 22,
        vertical: phone ? 13 : 16,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x12DDE6F4)),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: phone ? 38 : 46,
            height: phone ? 50 : 60,
            decoration: BoxDecoration(
              color: _blockColour(system, kind),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          SizedBox(width: phone ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(
                    size: phone ? 14 : 16,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(
                    size: phone ? 12 : 13,
                    color: Tokens.muted,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: phone ? 8 : 16),
          _StatusPill(kind: kind, phone: phone),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.kind, required this.phone});

  final _FileKind kind;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final (label, colour, icon) = switch (kind) {
      _FileKind.ready => ('Ready', Tokens.ok, Symbols.check),
      _FileKind.duplicate => (
        'Already added',
        Tokens.muted,
        Symbols.contentCopy,
      ),
      _FileKind.noCore => ('Skipped', Tokens.warn, Symbols.block),
      _FileKind.notGame => ('Skipped', Tokens.separator, Symbols.block),
    };
    return Container(
      height: phone ? 24 : 28,
      padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: phone ? 13 : 16, color: colour),
          const SizedBox(width: 6),
          Text(
            label,
            style: Tokens.body(
              size: phone ? 11 : 12,
              weight: FontWeight.w700,
              color: colour,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.ready,
    required this.duplicate,
    required this.noCore,
    required this.showGlyph,
    required this.compact,
    required this.busy,
    required this.onAdd,
    required this.onBack,
  });

  final int ready;
  final int duplicate;
  final int noCore;
  final bool showGlyph;
  final bool compact;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onBack;

  String get _paragraph {
    final parts = <String>[];
    if (duplicate > 0) {
      parts.add(
        duplicate == 1
            ? 'One file was already in your collection'
            : '$duplicate files were already in your collection',
      );
    }
    if (noCore > 0) {
      parts.add(
        noCore == 1
            ? 'one needs a system you haven’t installed'
            : '$noCore need a system you haven’t installed',
      );
    }
    if (parts.isEmpty) {
      return 'Ready to add. Nothing has been copied or moved.';
    }
    final joined = parts.length == 1
        ? parts.first
        : '${parts.first} and ${parts.last}';
    return 'Ready to add. $joined. Nothing has been copied or moved.';
  }

  @override
  Widget build(BuildContext context) {
    final label = ready == 1 ? 'Add 1 game' : 'Add $ready games';
    final primary = _OrbitAction(
      key: const Key('import-add-games'),
      label: label,
      glyph: showGlyph ? 'Enter' : null,
      primary: true,
      compact: compact,
      enabled: ready > 0 && !busy,
      onTap: onAdd,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ready == 1 ? '1 new' : '$ready new',
          style: Tokens.display(
            size: compact ? 54 : 64,
            weight: FontWeight.w700,
            ls: -0.04 * (compact ? 54 : 64),
            height: 1,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          // The design's flex gap (12) plus the paragraph's own bottom
          // margin (12) sit between the note and the primary action.
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(
            _paragraph,
            style: Tokens.body(
              size: compact ? 14 : 16,
              height: 1.55,
              color: Tokens.muted,
            ),
          ),
        ),
        primary,
        const SizedBox(height: 12),
        _OrbitAction(
          key: const Key('import-different-folder'),
          label: 'Choose a different folder',
          primary: false,
          compact: compact,
          enabled: !busy,
          onTap: onBack,
        ),
      ],
    );
  }
}

class _OrbitAction extends StatelessWidget {
  const _OrbitAction({
    super.key,
    required this.label,
    required this.primary,
    required this.compact,
    required this.enabled,
    required this.onTap,
    this.glyph,
  });

  final String label;
  final bool primary;
  final bool compact;
  final bool enabled;
  final VoidCallback onTap;
  final String? glyph;

  @override
  Widget build(BuildContext context) {
    final decoration = primary
        ? Tokens.primaryButton(
            state: enabled
                ? OrbitButtonState.rest
                : OrbitButtonState.disabled,
          )
        : Tokens.secondaryButton(
            state: enabled
                ? OrbitButtonState.rest
                : OrbitButtonState.disabled,
          );
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: SizedBox(
        height: compact ? 52 : 56,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: decoration,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (glyph != null) ...[
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      constraints: const BoxConstraints(minWidth: 24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        glyph!,
                        style: Tokens.display(
                          size: 12,
                          weight: FontWeight.w700,
                          ls: 0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: compact ? 14 : 16,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        height: 1,
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

// ---------------------------------------------------------------------------
// Advanced scan (existing actions, quiet by default)
// ---------------------------------------------------------------------------

class _AdvancedScan extends StatelessWidget {
  const _AdvancedScan({
    required this.open,
    required this.busy,
    required this.path,
    required this.onToggle,
    required this.onBrowse,
    required this.onScanPath,
    required this.onAddFolder,
    required this.onRescan,
    required this.folders,
    required this.onRemoveFolder,
    required this.rescanSummary,
  });

  final bool open;
  final bool busy;
  final TextEditingController path;
  final VoidCallback onToggle;
  final VoidCallback onBrowse;
  final VoidCallback onScanPath;
  final VoidCallback onAddFolder;
  final VoidCallback onRescan;
  final List<String> folders;
  final ValueChanged<String> onRemoveFolder;
  final String? rescanSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const Key('import-advanced-toggle'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.tune, size: 18, color: Tokens.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Scan a path or manage watched folders',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(size: 13, color: Tokens.muted),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Symbols.expandMore,
                  size: 18,
                  color: Tokens.muted,
                ),
              ],
            ),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('import-path-field'),
                  controller: path,
                  enabled: !busy,
                  style: Tokens.body(size: 13),
                  decoration: const InputDecoration(
                    labelText: 'File or folder path',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SmallAction(
                      label: 'Browse files',
                      icon: Symbols.folderOpen,
                      onTap: busy ? null : onBrowse,
                    ),
                    _SmallAction(
                      label: 'Scan typed path',
                      icon: Symbols.search,
                      onTap: busy ? null : onScanPath,
                    ),
                    _SmallAction(
                      key: const Key('import-add-folder'),
                      label: 'Add ROM folder to watch list',
                      icon: Symbols.folderSpecial,
                      onTap: busy ? null : onAddFolder,
                    ),
                    _SmallAction(
                      key: const Key('import-rescan'),
                      label: 'Re-scan ROM folders',
                      icon: Symbols.refresh,
                      onTap: busy ? null : onRescan,
                    ),
                  ],
                ),
                if (folders.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'WATCHED FOLDERS',
                    style: Tokens.body(
                      size: 12,
                      weight: FontWeight.w600,
                      ls: 1.5,
                      color: Tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final folder in folders)
                        InputChip(
                          key: Key('remove-folder-$folder'),
                          label: Text(folder, style: Tokens.body(size: 12)),
                          onDeleted: busy
                              ? null
                              : () => onRemoveFolder(folder),
                          deleteIcon:
                              const Icon(Symbols.close, size: 16),
                        ),
                    ],
                  ),
                ],
                if (rescanSummary != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    rescanSummary!,
                    style: Tokens.body(size: 13, color: Tokens.ok),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: Tokens.secondaryButton(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: Tokens.text),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Tokens.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: Tokens.text,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small formatting helpers
// ---------------------------------------------------------------------------

/// "ember-circuit.gba" -> "Ember Circuit" for the review row.
String _prettyName(String filePath) {
  final name = filePath.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  var stem = dot > 0 ? name.substring(0, dot) : name;
  // A region or revision tag is metadata, not part of the title.
  stem = stem.replaceAll(
    RegExp(r'\s*\((usa|europe|japan|world|rev [^)]*)\)',
        caseSensitive: false),
    '',
  );
  final words = stem
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty);
  return words
      .map((w) => w.length == 1
          ? w.toUpperCase()
          : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// The raw file name, for rows whose content is not a game.
String _fileName(String filePath) => filePath.split(RegExp(r'[\\/]')).last;

String _size(int bytes) {
  if (bytes <= 0) return 'unknown size';
  if (bytes >= 1 << 30) {
    final gb = bytes / (1 << 30);
    return '${gb.toStringAsFixed(1)} GB';
  }
  final mb = bytes / (1 << 20);
  if (mb >= 100) return '${mb.round()} MB';
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// A deterministic system colour block, drawn from the design's system
/// hues (oklch 0.47 0.095 H). Duplicates get the design's lighter block;
/// skipped files and non-games get the neutral slate.
Color _blockColour(String system, _FileKind kind) {
  switch (kind) {
    case _FileKind.noCore:
    case _FileKind.notGame:
      return const Color(0xFF38434C);
    case _FileKind.duplicate:
      return _oklch(0.52, 0.12, 270);
    case _FileKind.ready:
      break;
  }
  final hue = switch (system.toLowerCase()) {
    'nes' => 25.0,
    'snes' => 300.0,
    'n64' => 150.0,
    'gb' => 115.0,
    'gbc' => 345.0,
    'gba' => 270.0,
    'nds' => 215.0,
    'psx' || 'ps1' => 245.0,
    'dc' => 55.0,
    'psp' => 190.0,
    _ => 220.0,
  };
  return _oklch(0.47, 0.095, hue);
}

/// oklch → sRGB, so the system hues are the design's, not an HSL guess.
Color _oklch(double lightness, double chroma, double hueDegrees) {
  final h = hueDegrees * math.pi / 180;
  final a = chroma * math.cos(h);
  final b = chroma * math.sin(h);
  final l = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final m = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final s = lightness - 0.0894841775 * a - 1.2914855480 * b;
  final l3 = l * l * l;
  final m3 = m * m * m;
  final s3 = s * s * s;
  double gamma(double v) {
    final c = v.clamp(0.0, 1.0);
    return c <= 0.0031308
        ? 12.92 * c
        : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  }

  final r = gamma(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3);
  final g = gamma(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3);
  final bl = gamma(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3);
  return Color.fromARGB(
    255,
    (r * 255).round().clamp(0, 255).toInt(),
    (g * 255).round().clamp(0, 255).toInt(),
    (bl * 255).round().clamp(0, 255).toInt(),
  );
}
