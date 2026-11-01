import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../cores/core_registry.dart';
import '../models/core_manifest.dart';
import '../services/core_package_installer.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/hardware_art.dart';
import '../widgets/orbit_widgets.dart';

/// Systems — the cores that play them (Orbit §8.4).
///
/// A four-column grid of console cards, each showing its system, core and an
/// honest status, with a glass detail panel beside it on wide screens. The
/// Installed / Available tabs swap the catalog; installing a core from a file
/// is a first-class action in the detail panel.
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

  /// Core currently being installed or downloaded (single-flight).
  ///
  /// A notifier (rather than a plain field) so a modal core sheet can follow
  /// install progress while it is open: the sheet lives in its own route and
  /// does not rebuild with this screen.
  final ValueNotifier<String?> _busy = ValueNotifier<String?>(null);

  String? get _busyId => _busy.value;

  set _busyId(String? id) => _busy.value = id;

  AppState get state => widget.state;
  CoreRegistry get registry => state.registry;

  List<CoreManifest> get _visible => [
    for (final m in registry.catalog)
      if (registry.isInstalled(m.id) == _installedView) m,
  ];

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final phone = layout == OrbitLayout.phonePortrait;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          // One layout, five families: phone portrait turns the card grid into
          // a list (§10); every other family keeps the grid.
          final showPanel =
              layout == OrbitLayout.desktop ||
              (layout == OrbitLayout.tablet && c.maxWidth >= 1000);
          final side = phone ? 18.0 : (Layout.isPhone(layout) ? 20.0 : 44.0);
          final top = phone ? 18.0 : (Layout.isShort(layout) ? 20.0 : 36.0);
          final bottom = showPanel
              ? 84.0
              : (Layout.isPhone(layout) ? 16.0 : 32.0);
          final list = _visible;
          final selected = showPanel && list.isNotEmpty
              ? list.where((m) => m.id == _selectedId).firstOrNull ?? list.first
              : null;
          // Width the grid actually gets beside the detail panel.
          final gridWidth = showPanel
              ? (c.maxWidth - side * 2 - 380 - 24).clamp(0.0, 830.0)
              : c.maxWidth - side * 2;
          final content = _content(
            list,
            selected,
            layout: layout,
            showPanel: showPanel,
            columns: _columnsFor(gridWidth, phone: phone),
          );
          final body = Padding(
            padding: EdgeInsets.fromLTRB(side, top, side, bottom),
            child: content,
          );
          if (!showPanel) return body;
          return Padding(
            padding: EdgeInsets.fromLTRB(side, top, side, bottom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 830),
                      child: content,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 380,
                  child: selected == null
                      ? const SizedBox.shrink()
                      : _CoreDetail(
                          key: ValueKey(selected.id),
                          manifest: selected,
                          state: state,
                          busy: _busyId == selected.id,
                          actions: this,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Card columns for a given grid width. Phone portrait is a list.
  int _columnsFor(double width, {required bool phone}) {
    if (phone) return 1;
    if (width < 360) return 1;
    if (width < 560) return 2;
    if (width < 780) return 3;
    return 4;
  }

  Widget _content(
    List<CoreManifest> list,
    CoreManifest? selected, {
    required OrbitLayout layout,
    required bool showPanel,
    required int columns,
  }) {
    final phone = layout == OrbitLayout.phonePortrait;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: phone ? 0 : 4),
          child: _header(small: Layout.isPhone(layout)),
        ),
        SizedBox(height: phone ? 16 : (Layout.isShort(layout) ? 12 : 15)),
        _tabs(),
        SizedBox(height: phone ? 14 : (Layout.isShort(layout) ? 16 : 22)),
        Expanded(
          child: phone
              ? _list(list, _selectedId)
              : _grid(
                  list,
                  selected,
                  wide: showPanel,
                  compact: Layout.isShort(layout),
                  columns: columns,
                ),
        ),
      ],
    );
  }

  Widget _header({required bool small}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'THE CORES THAT PLAY THEM',
          style: Tokens.eyebrow.copyWith(color: Tokens.muted, height: 1),
        ),
        const SizedBox(height: 8),
        Text(
          'Systems',
          style: Tokens.displayScreen.copyWith(
            // Phones hold the ×0.85 type scale (§3.2): 44 → 37.4.
            fontSize: small ? Tokens.screenTitle * 0.85 : Tokens.screenTitle,
          ),
        ),
      ],
    );
  }

  Widget _tabs() {
    final installed = registry.installedCores.length;
    final available = registry.catalog.length - installed;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SystemsTab(
            label: 'Installed',
            count: installed,
            active: _installedView,
            onTap: () => setState(() {
              _installedView = true;
              _selectedId = null;
            }),
          ),
          const SizedBox(width: 8),
          _SystemsTab(
            label: 'Available',
            count: available,
            active: !_installedView,
            onTap: () => setState(() {
              _installedView = false;
              _selectedId = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    List<CoreManifest> list,
    CoreManifest? selected, {
    required bool wide,
    required bool compact,
    required int columns,
  }) {
    if (list.isEmpty) {
      return Align(alignment: Alignment.topLeft, child: _emptyMessage(compact));
    }
    return GridView.builder(
      padding: EdgeInsets.only(bottom: compact ? 8 : 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: 236,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        final busy = _busyId == m.id;
        final status = coreStatus(m, busy: busy);
        return _CoreCard(
          manifest: m,
          title: coreTitle(m),
          status: status,
          // The check marks a core that is installed and ready to play.
          showCheck: !busy && status.color == Tokens.ok,
          busy: busy,
          selected: wide && selected?.id == m.id,
          onTap: () => _open(m, wide),
        );
      },
    );
  }

  /// Phone portrait: the grid becomes a list (§10), one row per core.
  ///
  /// Rows carry the name and the coloured status only — the art thumb is the
  /// placeholder tile, and tapping a row opens the same detail as the desktop
  /// panel, as a sheet from the bottom edge.
  Widget _list(List<CoreManifest> list, String? selectedId) {
    if (list.isEmpty) {
      return Align(alignment: Alignment.topLeft, child: _emptyMessage(true));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final m = list[i];
        final busy = _busyId == m.id;
        return _CoreRow(
          key: ValueKey('row-${m.id}'),
          manifest: m,
          title: coreTitle(m),
          status: coreStatus(m, busy: busy),
          busy: busy,
          selected: selectedId == m.id,
          onTap: () => _openSheet(m),
        );
      },
    );
  }

  Widget _emptyMessage(bool compact) {
    final available = !_installedView;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          available
              ? 'Every core in the catalog is installed.'
              : 'No cores installed yet. Pick one from Available, or install '
                    'one from a file.',
          style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
        ),
        if (available) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: compact ? double.infinity : 260,
            child: _PanelButton(
              label: 'Install core from file',
              icon: Icons.folder_open_outlined,
              onPressed: installPackageFlow,
            ),
          ),
        ],
      ],
    );
  }

  /// Opens [m]: beside the grid on wide screens, as its own page elsewhere.
  void _open(CoreManifest m, bool wide) {
    if (wide) {
      setState(() => _selectedId = m.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Tokens.bg,
            appBar: AppBar(backgroundColor: Colors.transparent),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
          ),
        ),
      );
    }
  }

  /// Phones: the detail is a bottom sheet (the desktop panel's content), so the
  /// list stays in view behind it.
  Future<void> _openSheet(CoreManifest m) {
    setState(() => _selectedId = m.id);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Tokens.bg.withValues(alpha: 0.6),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.86,
        child: ListenableBuilder(
          listenable: Listenable.merge([state, _busy]),
          builder: (context, _) => _CoreDetail(
            manifest: m,
            state: state,
            busy: _busyId == m.id,
            actions: this,
            inSheet: true,
          ),
        ),
      ),
    );
  }

  // ---- status and trust, in plain words ----

  /// One honest line about whether this core can be used here.
  ({String text, Color color}) coreStatus(CoreManifest m, {bool busy = false}) {
    if (busy) return (text: 'Installing…', color: Tokens.systemLabelFg);
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
    if (m.biosRequired) {
      return (text: 'Not installed · needs BIOS', color: Tokens.muted);
    }
    return (text: 'Not installed · ready to install', color: Tokens.muted);
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
              ? '${coreTitle(m)} downloaded and verified'
              : '${coreTitle(m)} is ready',
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

/// One pill of the Installed / Available switch.
class _SystemsTab extends StatelessWidget {
  const _SystemsTab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Tokens.muted;
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $count',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: Tokens.chipPill(active: active),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Tokens.body(
                    size: 14,
                    weight: FontWeight.w600,
                    color: foreground,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: Tokens.body(
                    size: 14,
                    color: foreground.withValues(alpha: 0.6),
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

/// Phone portrait: one core as a full-width list row.
///
/// 56 px art thumb, the system name, a coloured status line and a trailing
/// state icon; an installing row draws its progress bar along the bottom edge.
class _CoreRow extends StatefulWidget {
  const _CoreRow({
    super.key,
    required this.manifest,
    required this.title,
    required this.status,
    required this.busy,
    required this.selected,
    required this.onTap,
  });

  final CoreManifest manifest;
  final String title;
  final ({String text, Color color}) status;
  final bool busy;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CoreRow> createState() => _CoreRowState();
}

class _CoreRowState extends State<_CoreRow> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.selected || _hover || _focus;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.title}. ${widget.status.text}',
      child: FocusableActionDetector(
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
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
            height: 76,
            clipBehavior: Clip.antiAlias,
            decoration: (lit
                    ? Tokens.coreCardSelectedDecor
                    : Tokens.coreCardDecor)
                .copyWith(borderRadius: BorderRadius.circular(16)),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 56,
                        child: CoreConsoleArt(
                          coreId: widget.manifest.id,
                          systems: widget.manifest.systems,
                          radius: 10,
                          showLabel: false,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Tokens.body(
                                size: 17,
                                weight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.status.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Tokens.body(
                                size: 13,
                                weight: FontWeight.w600,
                                color: widget.status.color,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ExcludeSemantics(child: _trailing()),
                    ],
                  ),
                ),
                if (widget.busy)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: Tokens.accent,
                      backgroundColor: Tokens.systemLabelBg,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailing() {
    if (widget.busy) {
      return SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: Tokens.systemLabelFg,
        ),
      );
    }
    if (widget.status.color == Tokens.ok) {
      return const Icon(Icons.check_circle, size: 22, color: Tokens.ok);
    }
    if (widget.status.color == Tokens.warn) {
      return const Icon(Icons.warning_rounded, size: 22, color: Tokens.warn);
    }
    return const SizedBox.shrink();
  }
}

/// A core as a console card: art, system, core and status.
class _CoreCard extends StatefulWidget {
  const _CoreCard({
    required this.manifest,
    required this.title,
    required this.status,
    required this.showCheck,
    required this.busy,
    required this.selected,
    required this.onTap,
  });

  final CoreManifest manifest;
  final String title;
  final ({String text, Color color}) status;
  final bool showCheck;
  final bool busy;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CoreCard> createState() => _CoreCardState();
}

class _CoreCardState extends State<_CoreCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.selected || _hover || _focus;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.title}. ${widget.status.text}',
      child: FocusableActionDetector(
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
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
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusCoreCard),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B2A3D), Color(0xFF0C1522)],
                stops: [0.0, 0.65],
              ),
              border: lit ? null : Border.all(color: const Color(0x24DDE6F4)),
              boxShadow: lit ? Tokens.halo : null,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  right: 14,
                  top: 14,
                  height: 118,
                  child: CoreConsoleArt(
                    coreId: widget.manifest.id,
                    systems: widget.manifest.systems,
                  ),
                ),
                if (widget.showCheck)
                  Positioned(
                    right: 20,
                    top: 20,
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.check_circle,
                        size: 22,
                        color: Tokens.ok,
                      ),
                    ),
                  ),
                Positioned(
                  left: 18,
                  right: 18,
                  top: 146,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 16,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${widget.manifest.name} ${widget.manifest.version}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 13,
                          color: Tokens.muted,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.status.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 13,
                          weight: FontWeight.w600,
                          color: widget.status.color,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.busy)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: Tokens.accent,
                      backgroundColor: Colors.transparent,
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

/// The green outline "Verified" pill (amber for an unverified package).
class _TrustPill extends StatelessWidget {
  const _TrustPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final verified = label == 'Verified';
    final color = verified ? Tokens.ok : Tokens.warn;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Tokens.body(
          size: 12,
          weight: FontWeight.w600,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}

/// A 50 px panel button: primary fill or quiet secondary.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = primary ? Colors.white : Tokens.text;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
            child: Container(
              height: 50,
              decoration: primary
                  ? Tokens.primaryButton()
                  : Tokens.secondaryButton(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: foreground,
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

/// Everything about one core and every action on it.
class _CoreDetail extends StatelessWidget {
  const _CoreDetail({
    super.key,
    required this.manifest,
    required this.state,
    required this.busy,
    required this.actions,
    this.inSheet = false,
  });

  final CoreManifest manifest;
  final AppState state;
  final bool busy;
  final _CoreManagerScreenState actions;

  /// Phones present this content in a bottom sheet rather than the side panel.
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final installed = state.registry.isInstalled(m.id);
    final trust = actions.trustLabel(m);
    final exts = m.extensions.map((e) => '.$e').join(' ');
    final canAdd = actions.canAdd(m);

    Widget fact(String label, String value, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x0FDDE6F4))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Tokens.body(size: 13.5, color: Tokens.muted, height: 1.45),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Tokens.body(
                size: 13.5,
                color: color ?? Tokens.text,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      // A bottom sheet gets the modal surface (top corners only); the desktop
      // side panel keeps the glass panel and its uniform ring.
      decoration: inSheet
          ? Tokens.sheetDecor
          // A uniform ring: a border with per-side colours cannot be painted
          // on a rounded surface.
          : Tokens.panelGlass.copyWith(
              border: Border.all(color: Tokens.lineStrong),
            ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          inSheet ? 16 : 24,
          24,
          24 + (inSheet ? MediaQuery.paddingOf(context).bottom : 0),
        ),
        children: [
          if (inSheet) ...[
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Tokens.lineStrong,
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          SizedBox(
            height: 170,
            child: CoreConsoleArt(coreId: m.id, systems: m.systems),
          ),
          const SizedBox(height: 14),
          Text(
            coreTitle(m),
            style: Tokens.displayPanel.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${m.name} ${m.version}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(size: 14, color: Tokens.muted, height: 1),
                ),
              ),
              const SizedBox(width: 10),
              _TrustPill(label: trust),
            ],
          ),
          const SizedBox(height: 18),
          if (installed) ...[
            _PanelButton(
              label: 'Show games',
              icon: Icons.grid_view,
              primary: true,
              onPressed: () => actions.showGames(m),
            ),
            const SizedBox(height: 8),
            _PanelButton(
              label: 'Remove',
              icon: Icons.delete_outline,
              onPressed: busy ? null : () => actions.confirmRemove(m),
            ),
          ] else ...[
            _PanelButton(
              label: busy ? 'Installing…' : 'Install',
              icon: Icons.download,
              primary: true,
              onPressed: busy || !canAdd ? null : () => actions.install(m),
            ),
            const SizedBox(height: 8),
            _PanelButton(
              label: 'Install core from file',
              icon: Icons.folder_open_outlined,
              onPressed: busy ? null : actions.installPackageFlow,
            ),
          ],
          const SizedBox(height: 20),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1ADDE6F4))),
            ),
            child: Column(
              children: [
                fact('Plays', exts.isEmpty ? '—' : exts),
                fact('Licence', m.license.isEmpty ? '—' : m.license),
                fact(
                  'BIOS',
                  m.biosRequired
                      ? 'Required: ${m.biosFiles.join(', ')}. You supply these '
                            'from hardware you own.'
                      : 'Not required',
                  color: m.biosRequired && installed ? Tokens.warn : null,
                ),
                fact(
                  'Source',
                  installed
                      ? 'Installed from the app bundle'
                      : 'Bundled with ezCORE · installs offline',
                ),
                fact(
                  'Trust',
                  trust == 'Verified'
                      ? 'Built and checked by the ezCORE project.'
                      : 'Installed by you from a file. Not reviewed by the '
                            'project and never updated automatically.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Add-on systems whose hardware is implied by a base system's name.
const _addOnSystems = <String, String>{
  'Famicom Disk System': 'Nintendo Entertainment System',
};

/// A core is named by what it plays: "Game Boy Advance, Game Boy". A label
/// that is only another name of one already listed is dropped ("PC Engine /
/// TurboGrafx-16" already says "TurboGrafx-16"); a label merely containing
/// another ("Game Boy" in "Game Boy Advance") is a different system and
/// stays. Long lists end in "+N".
String coreTitle(CoreManifest m) {
  final labels = m.systems.map(systemLabel).toList();
  final present = labels.toSet();
  final kept = <String>[];
  final names = <String>{};
  for (final label in labels) {
    if (names.contains(label)) continue;
    // An add-on is not a second system title when the base system is listed:
    // the Famicom Disk System plays NES games, so the card reads "Nintendo
    // Entertainment System", not a list of two.
    final base = _addOnSystems[label];
    if (base != null && present.contains(base)) continue;
    kept.add(label);
    names
      ..add(label)
      ..addAll(label.split(' / ').map((n) => n.trim()));
  }
  if (kept.length <= 3) return kept.join(', ');
  return '${kept.take(3).join(', ')} +${kept.length - 3}';
}
