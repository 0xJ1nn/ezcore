import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../cores/core_registry.dart';
import '../models/core_manifest.dart';
import '../services/core_package_installer.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/collection_view.dart';
import '../widgets/cover_flow.dart';
import '../widgets/focus_glow.dart';
import '../widgets/hardware_art.dart';
import '../widgets/orbit_widgets.dart';

/// Cores — the platform's "apps" (layout option A).
///
/// A list of cores named by the systems they play, with a plain status and a
/// trust label; a detail panel beside it on wide screens and a page of its
/// own on phones. Installed and Available are the two views; installing a
/// core from a file is a first-class action, not a hidden icon.
class CoreManagerScreen extends StatefulWidget {
  const CoreManagerScreen({super.key, required this.state, this.onBrowseCore});
  final AppState state;

  /// Shows the library for a core's games.
  final ValueChanged<String>? onBrowseCore;

  @override
  State<CoreManagerScreen> createState() => _CoreManagerScreenState();
}

class _CoreManagerScreenState extends State<CoreManagerScreen> {
  bool _installedView = true;
  String? _selectedId;
  int _flowIndex = 0;

  /// Core currently being installed or downloaded (single-flight).
  String? _busyId;

  AppState get state => widget.state;
  CoreRegistry get registry => state.registry;

  CollectionView get _view => CollectionView.fromSetting(
    state.settings[coresViewKey],
    fallback: CollectionView.flow,
  );

  void _setView(CollectionView v) => state.setSetting(coresViewKey, v.value);

  List<CoreManifest> get _visible => [
    for (final m in registry.catalog)
      if (registry.isInstalled(m.id) == _installedView) m,
  ]..sort((a, b) => _title(a).compareTo(_title(b)));

  static String _title(CoreManifest m) => coreTitle(m);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final compact = c.maxWidth < 600;
          final pad = compact ? 16.0 : (c.maxWidth >= 1180 ? 40.0 : 24.0);
          final list = _visible;
          final flowIndex = list.isEmpty
              ? 0
              : _flowIndex.clamp(0, list.length - 1);
          final selected = _view == CollectionView.flow
              ? (wide && list.isNotEmpty ? list[flowIndex] : null)
              : list.where((m) => m.id == _selectedId).firstOrNull ??
                    (wide && list.isNotEmpty ? list.first : null);
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, compact ? 16 : 28, pad, 16),
                child: _header(compact),
              ),
              Expanded(
                child: switch (_view) {
                  CollectionView.list => _list(list, selected, pad, wide),
                  CollectionView.grid => _grid(list, selected, pad, wide),
                  CollectionView.flow => _flow(
                    list,
                    flowIndex,
                    pad,
                    wide,
                    compact,
                  ),
                },
              ),
            ],
          );
          if (!wide || selected == null) return body;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: body),
              Padding(
                padding: EdgeInsets.fromLTRB(0, 28, pad, 24),
                child: SizedBox(
                  width: 360,
                  child: _CoreDetail(
                    key: ValueKey(selected.id),
                    manifest: selected,
                    state: state,
                    busy: _busyId == selected.id,
                    actions: this,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(bool compact) {
    final installed = registry.installedCores.length;
    final available = registry.catalog.length - installed;
    final tabs = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrbitChip(
          label: 'Installed · $installed',
          active: _installedView,
          onTap: () => setState(() {
            _installedView = true;
            _selectedId = null;
            _flowIndex = 0;
          }),
        ),
        const SizedBox(width: 8),
        OrbitChip(
          label: 'Available · $available',
          active: !_installedView,
          onTap: () => setState(() {
            _installedView = false;
            _selectedId = null;
            _flowIndex = 0;
          }),
        ),
      ],
    );
    final install = compact
        ? OrbitIconButton(
            icon: Icons.download_outlined,
            tooltip: 'Install core from file',
            onPressed: installPackageFlow,
          )
        : OrbitSecondary(
            label: 'Install core from file',
            icon: Icons.download_outlined,
            onPressed: installPackageFlow,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'THE CORES THAT PLAY THEM',
                    style: Tokens.body(
                      size: 11,
                      weight: FontWeight.w600,
                      ls: 4,
                      color: Tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Systems',
                    style: Tokens.display(
                      size: compact ? 28 : 40,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            CollectionViewSwitch(value: _view, onChanged: _setView),
            const SizedBox(width: 12),
            install,
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
      ],
    );
  }

  Widget _emptyMessage(double pad) => Padding(
    padding: EdgeInsets.symmetric(horizontal: pad),
    child: Text(
      _installedView
          ? 'No cores installed yet. Pick one from Available, or install '
                'one from a file.'
          : 'Every core in the catalog is installed.',
      style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
    ),
  );

  Widget _grid(
    List<CoreManifest> list,
    CoreManifest? selected,
    double pad,
    bool wide,
  ) {
    if (list.isEmpty) return _emptyMessage(pad);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        return _CoreCard(
          manifest: m,
          title: _title(m),
          status: coreStatus(m),
          trust: trustLabel(m),
          selected: wide && selected?.id == m.id,
          busy: _busyId == m.id,
          onTap: () => _open(m, wide),
        );
      },
    );
  }

  /// The 3D shelf of cores. Wide screens show the front core's details
  /// beside it; phones get a caption and a Details button underneath.
  Widget _flow(
    List<CoreManifest> list,
    int index,
    double pad,
    bool wide,
    bool compact,
  ) {
    if (list.isEmpty) return _emptyMessage(pad);
    final front = list[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final h = (c.maxHeight * 0.8).clamp(96.0, 360.0);
              final w = (h * 0.82).clamp(
                64.0,
                c.maxWidth * (compact ? 0.6 : 0.36),
              );
              return CoverFlow(
                count: list.length,
                index: index,
                itemSize: Size(w, w / 0.82),
                showArrows: !compact,
                semanticLabel: 'Cores',
                onIndexChanged: (i) => setState(() => _flowIndex = i),
                onActivate: (i) => _open(list[i], wide),
                itemBuilder: (context, i, isFront) => _CoreCard(
                  manifest: list[i],
                  title: _title(list[i]),
                  status: coreStatus(list[i]),
                  trust: trustLabel(list[i]),
                  selected: isFront,
                  busy: _busyId == list[i].id,
                  onTap: null,
                ),
              );
            },
          ),
        ),
        // The card shows the name and status, and wide screens show the
        // details beside the shelf: underneath, only where you are, plus the
        // way to the details on phones.
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, compact ? 12 : 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${(index + 1).toString().padLeft(2, '0')}  /  '
                  '${list.length.toString().padLeft(2, '0')}',
                  textAlign: wide ? TextAlign.center : TextAlign.start,
                  style: Tokens.body(
                    size: 11,
                    weight: FontWeight.w700,
                    ls: 1.4,
                    color: Tokens.muted,
                  ),
                ),
              ),
              if (!wide)
                OrbitPrimary(
                  label: 'Details',
                  icon: Icons.chevron_right,
                  minHeight: 46,
                  onPressed: () => _open(front, wide),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(
    List<CoreManifest> list,
    CoreManifest? selected,
    double pad,
    bool wide,
  ) {
    if (list.isEmpty) return _emptyMessage(pad);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = list[i];
        return _CoreRow(
          manifest: m,
          title: _title(m),
          status: coreStatus(m),
          trust: trustLabel(m),
          selected: wide && selected?.id == m.id,
          busy: _busyId == m.id,
          onTap: () => _open(m, wide),
        );
      },
    );
  }

  /// Opens [m]: beside the list on wide screens, as its own page on phones.
  void _open(CoreManifest m, bool wide) {
    if (wide) {
      setState(() => _selectedId = m.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Tokens.bg,
            appBar: AppBar(backgroundColor: Tokens.bg),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListenableBuilder(
                  listenable: state,
                  builder: (context, _) => _CoreDetail(
                    manifest: m,
                    state: state,
                    busy: _busyId == m.id,
                    actions: this,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  // ---- status and trust, in plain words ----

  /// One honest line about whether this core can be used here.
  ({String text, Color color}) coreStatus(CoreManifest m) {
    if (m.blocked) return (text: 'On hold', color: Tokens.muted);
    final delivery = m.delivery[Platform.operatingSystem];
    if (registry.isInstalled(m.id)) {
      if (registry.statusOf(m) == CoreStatus.updateAvailable) {
        return (text: 'Update available', color: Tokens.systemLabelFg);
      }
      if (m.biosRequired) {
        return (text: 'Ready · needs BIOS files', color: Tokens.ok);
      }
      return (text: 'Ready', color: Tokens.ok);
    }
    if (delivery == null || delivery == 'absent') {
      return (text: 'Not available on this device', color: Tokens.muted);
    }
    if (delivery == 'download') {
      return (text: 'Download to install', color: Tokens.systemLabelFg);
    }
    return (text: 'Ready to add', color: Tokens.systemLabelFg);
  }

  String trustLabel(CoreManifest m) =>
      registry.isUserPackage(m.id) ? 'Unverified' : 'Verified';

  bool canAdd(CoreManifest m) {
    final d = m.delivery[Platform.operatingSystem];
    return !m.blocked && d != null && d != 'absent';
  }

  // ---- actions ----

  Future<void> installPackageFlow() async {
    if (_busyId != null) return;
    final dirPath = await getDirectoryPath();
    if (dirPath == null || !mounted) return;
    var coreId = 'this core';
    try {
      final raw =
          jsonDecode(await File('$dirPath/manifest.json').readAsString())
              as Map<String, dynamic>;
      coreId = raw['id'] as String? ?? coreId;
    } catch (_) {
      // No readable manifest — the installer reports it precisely.
    }
    if (!mounted) return;
    final consented = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.panel,
        title: Text('Install $coreId?', style: Tokens.display(size: 20)),
        content: Text(
          'This installs emulator code from a folder on this device. Cores '
          'installed this way are labelled Unverified: the project has not '
          'reviewed them, they never update by themselves, and they run only '
          'because you chose to install them. Your games and saves are not '
          'touched.',
          style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (consented != true || !mounted) return;
    setState(() => _busyId = coreId);
    try {
      final report = await PackageInstaller().install(
        Directory(dirPath),
        userConsented: true,
      );
      if (!mounted) return;
      orbitToast(
        context,
        report.ok
            ? '${report.coreId} installed (unverified)'
            : 'Not installed: ${report.errors.isNotEmpty ? report.errors.first : report.refusedCode}',
      );
      if (report.ok) await state.rediscoverCores();
    } catch (e) {
      if (mounted) {
        orbitToast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> install(CoreManifest m) async {
    if (_busyId != null) return;
    final downloads = state.needsDownload(m);
    setState(() => _busyId = m.id);
    try {
      await state.addCore(m);
      if (mounted) {
        orbitToast(
          context,
          downloads
              ? '${_title(m)} downloaded and verified'
              : '${_title(m)} is ready',
        );
      }
    } catch (e) {
      if (mounted) {
        orbitToast(context, e.toString().replaceFirst('StateError: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> confirmRemove(CoreManifest m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.panel,
        title: Text('Remove ${m.name}?', style: Tokens.display(size: 20)),
        content: Text(
          'Your games and saves stay. You can install this core again any '
          'time.',
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
    registry.remove(m.id);
    orbitToast(context, '${m.name} removed — games and saves kept');
  }

  void showGames(CoreManifest m) {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    widget.onBrowseCore?.call(m.id);
  }
}

class _CoreRow extends StatelessWidget {
  const _CoreRow({
    required this.manifest,
    required this.title,
    required this.status,
    required this.trust,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final CoreManifest manifest;
  final String title;
  final ({String text, Color color}) status;
  final String trust;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    return FocusGlow(
      onTap: onTap,
      lift: 1.01,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0x1A007BFF) : const Color(0x0CDDE6F4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0x66007BFF) : Tokens.line,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 56,
                height: 56,
                color: Tokens.dockTop,
                child: Image.asset(
                  hardwareArtworkAsset(m.id, systems: m.systems),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.memory, color: Tokens.muted),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(size: 15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${m.name} ${m.version}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(size: 12, color: Tokens.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    busy ? 'Working…' : status.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(size: 12, color: status.color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _TrustBadge(label: trust),
          ],
        ),
      ),
    );
  }
}

/// A core as a card: its hardware art large, then name, status and trust.
class _CoreCard extends StatelessWidget {
  const _CoreCard({
    required this.manifest,
    required this.title,
    required this.status,
    required this.trust,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final CoreManifest manifest;
  final String title;
  final ({String text, Color color}) status;
  final String trust;
  final bool selected;
  final bool busy;

  /// Null inside the 3D shelf, which handles taps itself.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final card = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tokens.dockTop, Tokens.dockBottom],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? const Color(0x99007BFF) : Tokens.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  hardwareArtworkAsset(m.id, systems: m.systems),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.memory, size: 40, color: Tokens.muted),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: _TrustIcon(label: trust),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.body(size: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            busy ? 'Working…' : status.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.body(size: 12, color: status.color),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return FocusGlow(
      onTap: onTap!,
      lift: 1.02,
      semanticLabel: title,
      child: card,
    );
  }
}

/// Trust as a small icon, for cards too narrow for the worded badge.
class _TrustIcon extends StatelessWidget {
  const _TrustIcon({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final verified = label == 'Verified';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(
          verified ? Icons.verified_outlined : Icons.gpp_maybe_outlined,
          size: 18,
          color: verified ? Tokens.ok : const Color(0xFFFFC46B),
        ),
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final verified = label == 'Verified';
    final color = verified ? Tokens.ok : const Color(0xFFFFC46B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: Tokens.body(size: 11, color: color)),
    );
  }
}

/// Everything about one core and every action on it.
class _CoreDetail extends StatelessWidget {
  const _CoreDetail({
    super.key,
    required this.manifest,
    required this.state,
    required this.busy,
    required this.actions,
  });

  final CoreManifest manifest;
  final AppState state;
  final bool busy;
  final _CoreManagerScreenState actions;

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final installed = state.registry.isInstalled(m.id);
    final status = actions.coreStatus(m);
    final trust = actions.trustLabel(m);
    final exts = m.extensions.map((e) => '.$e').join('  ');
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Tokens.body(size: 12, color: Tokens.muted),
            ),
          ),
          Expanded(child: Text(value, style: Tokens.body(size: 13))),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: Tokens.panel,
        borderRadius: BorderRadius.circular(Tokens.dockPanelRadius),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: SizedBox(
              height: 120,
              child: Image.asset(
                hardwareArtworkAsset(m.id, systems: m.systems),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _CoreManagerScreenState._title(m),
            style: Tokens.display(size: 22, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${m.name} ${m.version}',
            style: Tokens.body(size: 13, color: Tokens.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _TrustBadge(label: trust),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  busy ? 'Working…' : status.text,
                  style: Tokens.body(size: 13, color: status.color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (installed) ...[
            OrbitPrimary(
              label: 'Show games',
              icon: Icons.grid_view,
              expanded: true,
              minHeight: 46,
              onPressed: () => actions.showGames(m),
            ),
            const SizedBox(height: 8),
            OrbitSecondary(
              label: 'Remove',
              icon: Icons.delete_outline,
              onPressed: busy ? null : () => actions.confirmRemove(m),
            ),
          ] else if (actions.canAdd(m))
            OrbitPrimary(
              label: state.needsDownload(m) ? 'Download and install' : 'Add',
              icon: state.needsDownload(m) ? Icons.download : Icons.add,
              expanded: true,
              minHeight: 46,
              onPressed: busy ? null : () => actions.install(m),
            ),
          const SizedBox(height: 16),
          const Divider(color: Tokens.line),
          fact('Plays', exts.isEmpty ? '—' : exts),
          fact('Licence', m.license),
          fact(
            'BIOS',
            m.biosRequired
                ? 'Required: ${m.biosFiles.join(', ')}. You supply these from '
                      'hardware you own.'
                : 'Not required',
          ),
          fact(
            'Cheats',
            m.cheatsSupported
                ? 'Supported (${m.cheatFamilies.join(', ')})'
                : 'Not supported',
          ),
          fact(
            'Trust',
            trust == 'Verified'
                ? 'Built and checked by the ezCORE project.'
                : 'Installed by you from a file. Not reviewed by the project '
                      'and never updated automatically.',
          ),
          if (m.blocked) fact('On hold', m.blockedReason),
        ],
      ),
    );
  }
}

/// A core is named by what it plays: "Game Boy Advance, Game Boy". A label
/// that is only another name of one already listed is dropped ("PC Engine /
/// TurboGrafx-16" already says "TurboGrafx-16"); a label merely containing
/// another ("Game Boy" in "Game Boy Advance") is a different system and
/// stays. Long lists end in "+N".
String coreTitle(CoreManifest m) {
  final kept = <String>[];
  final names = <String>{};
  for (final label in m.systems.map(systemLabel)) {
    if (names.contains(label)) continue;
    kept.add(label);
    names
      ..add(label)
      ..addAll(label.split(' / ').map((n) => n.trim()));
  }
  if (kept.length <= 3) return kept.join(', ');
  return '${kept.take(3).join(', ')} +${kept.length - 3}';
}
