import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../cores/core_registry.dart';
import '../models/core_manifest.dart';
import '../services/bios_check.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/hardware_art.dart';
import '../widgets/orbit_widgets.dart';

/// Orbit Systems — 3D core browser + bottom core dock (final-01).
/// Preserves: catalog load, install (sha-pin), remove, license, blocked holds,
/// compatible-core counts, Browse-games handoff.
class CoreManagerScreen extends StatefulWidget {
  const CoreManagerScreen({super.key, required this.state, this.onBrowseCore});
  final AppState state;
  final ValueChanged<String>? onBrowseCore;

  @override
  State<CoreManagerScreen> createState() => _CoreManagerScreenState();
}

class _CoreManagerScreenState extends State<CoreManagerScreen> {
  final pageCtrl = PageController(viewportFraction: 0.52);
  String scope = 'all'; // all | added | available
  String? selectedId;

  /// Core currently being downloaded (ADR-013) — single-flight guard.
  String? _busyId;

  @override
  void dispose() {
    pageCtrl.dispose();
    super.dispose();
  }

  List<CoreManifest> get visible {
    final cat = widget.state.registry.catalog;
    final filtered = cat.where((m) {
      final installed = widget.state.registry.isInstalled(m.id);
      if (scope == 'added') return installed;
      if (scope == 'available') return !installed;
      return true;
    }).toList();
    return filtered;
  }

  CoreManifest? get selected {
    final v = visible;
    if (v.isEmpty) return null;
    if (selectedId != null && v.any((m) => m.id == selectedId)) {
      return v.firstWhere((m) => m.id == selectedId);
    }
    return v.first;
  }

  int get addedCount => widget.state.registry.installedCores.length;

  void _select(String id, {bool jump = false}) {
    setState(() => selectedId = id);
    if (jump && pageCtrl.hasClients) {
      final i = visible.indexWhere((m) => m.id == id);
      if (i >= 0) {
        pageCtrl.animateToPage(i, duration: Tokens.easeDur, curve: Tokens.ease);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // One breakpoint definition for the whole app (theme/layout.dart).
    final portrait = Layout.isPhone(Layout.of(context));
    final osPad = Tokens.osPad(size.width, portrait: portrait);
    return ListenableBuilder(
      listenable: widget.state.registry,
      builder: (context, _) {
        final list = visible;
        final sel = selected;
        final selIndex = sel == null
            ? 0
            : list.indexWhere((m) => m.id == sel.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(osPad, 22, osPad, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR HARDWARE. YOUR RULES.',
                          style: Tokens.eyebrow,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'The core collection',
                          style: Tokens.display(
                            size: portrait ? 28 : 32,
                            weight: FontWeight.w500,
                            ls: -1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$addedCount added · ${list.length - list.where((m) => widget.state.registry.isInstalled(m.id)).length + (scope == "all" ? 0 : 0)} available',
                    style: Tokens.body(size: 10, color: Tokens.muted),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(osPad, 22, osPad, 0),
              child: Row(
                children: [
                  if (portrait)
                    Expanded(
                      child: CoreScopes(
                        scope: scope,
                        expand: true,
                        onScope: (s) => setState(() {
                          scope = s;
                          selectedId = null;
                        }),
                      ),
                    )
                  else
                    CoreScopes(
                      scope: scope,
                      onScope: (s) => setState(() {
                        scope = s;
                        selectedId = null;
                      }),
                    ),
                  if (!portrait) ...[
                    const Spacer(),
                    Text(
                      'MODULAR BY DESIGN · PREVIEW CATALOG',
                      style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (list.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No cores here. Yet.',
                        style: Tokens.display(size: 25),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Switch to All cores to add or remove a core.',
                        style: Tokens.body(
                          size: 12,
                          color: Tokens.muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Expanded(child: _browser(list, selIndex, osPad)),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${(selIndex + 1).toString().padLeft(2, '0')} / ${list.length.toString().padLeft(2, '0')}',
                    style: Tokens.flowCount,
                  ),
                ),
              ),
              if (sel != null)
                Container(
                  margin: EdgeInsets.fromLTRB(osPad, 0, osPad, 12),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                  decoration: Tokens.dockDecor,
                  child: portrait ? _dockPortrait(sel) : _dockLandscape(sel),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _browser(List<CoreManifest> list, int selIndex, double osPad) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.5, 0.64),
                radius: 0.6,
                colors: [Color(0x15007BFF), Colors.transparent],
                stops: [0.0, 0.6],
              ),
            ),
          ),
        ),
        PageView.builder(
          controller: pageCtrl,
          itemCount: list.length,
          onPageChanged: (i) => setState(() => selectedId = list[i].id),
          itemBuilder: (context, i) {
            return AnimatedBuilder(
              animation: pageCtrl,
              builder: (context, child) {
                double delta = 0;
                if (pageCtrl.position.haveDimensions) {
                  delta = ((pageCtrl.page ?? selIndex.toDouble()) - i).clamp(
                    -3.0,
                    3.0,
                  );
                } else {
                  delta = (selIndex - i).toDouble().clamp(-3.0, 3.0);
                }
                final a = delta.abs();
                final angle = delta == 0
                    ? 0.0
                    : (delta > 0 ? 24.0 : -24.0) * math.pi / 180;
                final opacity = a > 3
                    ? 0.0
                    : a == 0
                    ? 1.0
                    : (0.68 - (a - 1) * 0.13).clamp(0.2, 0.68);
                return Opacity(
                  opacity: a == 0 ? 1.0 : opacity,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..rotateY(-angle),
                    child: _CoreCard(
                      manifest: list[i],
                      selected: i == selIndex,
                      installed: widget.state.registry.isInstalled(list[i].id),
                      onTap: () {
                        if (i == selIndex) {
                          _coreActions(list[i]);
                        } else {
                          _select(list[i].id, jump: true);
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          left: osPad,
          child: _FlowBtn(
            enabled: selIndex > 0,
            icon: Icons.chevron_left,
            onTap: () {
              final n = (selIndex - 1).clamp(0, list.length - 1);
              _select(list[n].id, jump: true);
            },
          ),
        ),
        Positioned(
          right: osPad,
          child: _FlowBtn(
            enabled: selIndex < list.length - 1,
            icon: Icons.chevron_right,
            onTap: () {
              final n = (selIndex + 1).clamp(0, list.length - 1);
              _select(list[n].id, jump: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _dockLandscape(CoreManifest m) {
    final installed = widget.state.registry.isInstalled(m.id);
    final count = widget.state.games.where((g) => g.coreId == m.id).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _dockCopy(m, count)),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OrbitPrimary(
                  label: 'Browse games',
                  icon: Icons.grid_view,
                  minHeight: 48,
                  onPressed: installed
                      ? () => widget.onBrowseCore?.call(m.id)
                      : null,
                ),
                const SizedBox(width: 8),
                OrbitSecondary(
                  label: installed
                      ? 'Remove core'
                      : _busyId == m.id
                      ? 'Downloading…'
                      : 'Add core',
                  icon: installed
                      ? Icons.close
                      : _busyId == m.id
                      ? Icons.downloading
                      : Icons.add,
                  onPressed: () => installed ? _confirmRemove(m) : _install(m),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x14DDE6F4))),
          ),
          padding: const EdgeInsets.only(top: 9),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 12,
                color: Color(0xFF8290A4),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  m.blocked
                      ? 'Hold · ${m.blockedReason} — games & saves are kept.'
                      : 'Cores install locally on this device. Removing one keeps games & saves.',
                  style: Tokens.body(size: 9, color: Color(0xFF8290A4)),
                ),
              ),
              TextButton(
                onPressed: () => _license(m),
                child: Text(
                  'License',
                  style: Tokens.body(size: 10, color: Tokens.systemLabelFg),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dockPortrait(CoreManifest m) {
    final installed = widget.state.registry.isInstalled(m.id);
    final count = widget.state.games.where((g) => g.coreId == m.id).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dockCopy(m, count),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OrbitPrimary(
                label: 'Browse games',
                icon: Icons.grid_view,
                minHeight: 46,
                expanded: true,
                onPressed: installed
                    ? () => widget.onBrowseCore?.call(m.id)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OrbitSecondary(
                label: installed
                    ? 'Remove'
                    : _busyId == m.id
                    ? 'Downloading…'
                    : 'Add core',
                icon: installed
                    ? Icons.close
                    : _busyId == m.id
                    ? Icons.downloading
                    : Icons.add,
                onPressed: () => installed ? _confirmRemove(m) : _install(m),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          m.blocked
              ? 'Hold · ${m.blockedReason}'
              : 'Cores install locally on this device.',
          style: Tokens.body(size: 8, color: Color(0xFF8290A4)),
        ),
      ],
    );
  }

  Widget _dockCopy(CoreManifest m, int count) {
    final status = widget.state.registry.statusOf(m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              m.id,
              style: Tokens.display(
                size: 10,
                color: Tokens.systemLabelFg,
                ls: 0,
              ),
            ),
            Text(
              '${_typeFor(m)} · ${_eraFor(m)}',
              style: Tokens.body(size: 9, color: Tokens.muted),
            ),
            _StatusDot(status: status),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          m.name,
          style: Tokens.display(size: 22, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 6),
        Text(
          '${_aboutFor(m)} ',
          style: Tokens.body(size: 11, color: Tokens.dockBody, height: 1.45),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '$count sample ${count == 1 ? 'game' : 'games'} in your library',
          style: Tokens.body(size: 11, color: Tokens.text),
        ),
        if (m.biosRequired)
          FutureBuilder(
            future: BiosCheck().check(m),
            builder: (context, snap) {
              final report = snap.data;
              final label = report == null
                  ? 'Checking BIOS…'
                  : report.satisfied
                  ? 'BIOS ready — ${report.present.length} file(s) in place'
                  : 'BIOS missing — ${report.missing.join(', ')}';
              final ok = report?.satisfied ?? false;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  label,
                  style: Tokens.body(
                    size: 11,
                    color: ok ? Tokens.ok : Tokens.accent,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  String _typeFor(CoreManifest m) {
    final s = m.systems.join(' ').toLowerCase();
    if (s.contains('game boy') || s.contains('ds') || s.contains('psp')) {
      return 'Handheld';
    }
    if (s.contains('arcade')) return 'Arcade';
    if (s.contains('dos') || s.contains('scumm')) return 'Computer';
    return 'Home console';
  }

  String _eraFor(CoreManifest m) {
    const eras = {
      'joystick': '1977',
      'realmode': '1981 onward',
      'nesbyte': '1983',
      'blastproc': '1985 — 1991',
      'cardcon': '1987',
      'pocketbit': '1989 — 1998',
      'gambatte': '1989 — 1998',
      'superfx': '1990',
      'geometry1': '1994',
      'twinsh': '1994',
      'rcp64': '1996',
      'dreamarc': '1998 — 2003',
      'advancebit': '2001',
      'powercube': '2001 — 2006',
      'dualscreen': '2004',
      'portcomp': '2004',
      'coinbox': 'Multi-era',
      'pointclick': 'Multi-era',
    };
    return eras[m.id] ?? m.version;
  }

  String _aboutFor(CoreManifest m) {
    const about = {
      'pocketbit':
          'Pocket-sized worlds from Nintendo\u2019s original handhelds.',
      'advancebit': 'A golden era, in your hands — vivid pixel worlds.',
      'gambatte': 'An alternative engine for the Game Boy family.',
      'nesbyte': 'Where so many adventures began — clean pixels.',
      'superfx': 'Sixteen bits. Infinite feeling.',
      'rcp64': 'The leap into three dimensions.',
      'dualscreen': 'Two screens, twice the possibility.',
      'powercube': 'Two generations of playful invention.',
      'geometry1': 'A new dimension of storytelling.',
      'portcomp': 'Console ambition, pocket form.',
      'blastproc': 'The many shades of Sega.',
      'twinsh': 'Arcade ambition at home.',
      'dreamarc': 'A future ahead of schedule.',
      'cardcon': 'Small hardware. Outsized imagination.',
      'joystick': 'The first living-room legends.',
      'coinbox': 'One more credit — the arcade, at home.',
      'realmode': 'Command prompts to impossible worlds.',
      'pointclick': 'Take your time. Talk to everyone.',
    };
    return about[m.id] ?? '${m.systems.join(' · ')} — ${m.license}.';
  }

  void _install(CoreManifest m) {
    if (_busyId != null) return;
    final downloads = widget.state.needsDownload(m);
    if (downloads) {
      setState(() => _busyId = m.id);
      orbitToast(context, 'Downloading ${m.id}…');
    }
    widget.state
        .addCore(m)
        .then((_) {
          if (!mounted) return;
          if (downloads) setState(() => _busyId = null);
          orbitToast(
            context,
            downloads
                ? '${m.id} downloaded — SHA-256 verified'
                : '${m.id} added — no package downloaded',
          );
        })
        .catchError((Object e) {
          if (!mounted) return;
          if (downloads) setState(() => _busyId = null);
          orbitToast(context, e.toString().replaceFirst('StateError: ', ''));
        });
  }

  void _confirmRemove(CoreManifest m) {
    showOrbitDialog(
      context,
      Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CORE MANAGEMENT / PREVIEW', style: Tokens.eyebrow),
            const SizedBox(height: 12),
            Text(
              'Remove ${m.id}?',
              style: Tokens.display(size: 30, weight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              'This removes ${m.name} from your added cores. Your games and saves stay untouched. You can add this core again at any time.',
              style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OrbitSecondary(
                  label: 'Keep core',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                OrbitPrimary(
                  label: 'Remove core',
                  icon: Icons.close,
                  minHeight: 46,
                  onPressed: () {
                    widget.state.registry.remove(m.id);
                    Navigator.of(context).pop();
                    orbitToast(context, '${m.id} removed · games & saves kept');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _license(CoreManifest m) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.panel,
        title: Text('${m.name} license', style: Tokens.display(size: 18)),
        content: Text(
          '${m.license}\n\nCheats: ${m.cheatsSupported ? m.cheatFamilies.join(', ') : 'not supported'}\nBIOS: ${m.biosRequired ? 'required — ${m.biosFiles.join(', ')}' : 'not required'}',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: Tokens.body(size: 12, color: Tokens.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _coreActions(CoreManifest m) {
    final installed = widget.state.registry.isInstalled(m.id);
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
              leading: const Icon(Icons.grid_view, color: Tokens.text),
              title: Text('Browse games', style: Tokens.body()),
              enabled: installed,
              onTap: () {
                Navigator.of(context).pop();
                if (installed) widget.onBrowseCore?.call(m.id);
              },
            ),
            ListTile(
              leading: Icon(
                installed ? Icons.close : Icons.add,
                color: Tokens.text,
              ),
              title: Text(
                installed ? 'Remove core' : 'Add core',
                style: Tokens.body(),
              ),
              onTap: () {
                Navigator.of(context).pop();
                installed ? _confirmRemove(m) : _install(m);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.description_outlined,
                color: Tokens.text,
              ),
              title: Text('License', style: Tokens.body()),
              onTap: () {
                Navigator.of(context).pop();
                _license(m);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CoreCard extends StatelessWidget {
  const _CoreCard({
    required this.manifest,
    required this.selected,
    required this.installed,
    required this.onTap,
  });
  final CoreManifest manifest;
  final bool selected;
  final bool installed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 300,
            height: 320,
            padding: const EdgeInsets.all(18),
            decoration: selected
                ? Tokens.coreCardSelectedDecor
                : Tokens.coreCardDecor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      _shortFor(manifest.id),
                      style: Tokens.display(
                        size: 10,
                        weight: FontWeight.w500,
                        ls: 2.0,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: installed
                                ? Tokens.accent
                                : const Color(0xFF788394),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          installed
                              ? 'ADDED'
                              : manifest.blocked
                              ? 'HOLD'
                              : 'AVAILABLE',
                          style: Tokens.body(
                            size: 8,
                            weight: FontWeight.w600,
                            ls: 1.0,
                            color: installed
                                ? Tokens.systemLabelFg
                                : Tokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: SvgPicture.string(
                      hardwareSvg(manifest.id),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Text(
                  manifest.name,
                  style: Tokens.display(
                    size: 16,
                    weight: FontWeight.w500,
                    ls: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  manifest.id,
                  style: Tokens.body(size: 10, ls: 0.5, color: Tokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortFor(String id) {
    const shorts = {
      'pocketbit': 'GB',
      'gambatte': 'GBC',
      'advancebit': 'GBA',
      'nesbyte': 'NES',
      'superfx': 'SNES',
      'blastproc': 'MD',
      'joystick': '2600',
      'realmode': 'DOS',
      'cardcon': 'PCE',
      'geometry1': 'PS',
      'rcp64': 'N64',
      'dualscreen': 'DS',
      'portcomp': 'PSP',
      'dreamarc': 'DC',
      'powercube': 'GC',
      'twinsh': 'SAT',
      'coinbox': 'ARC',
      'pointclick': 'ADV',
    };
    return shorts[id] ?? id.toUpperCase();
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final CoreStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      CoreStatus.installed => Tokens.ok,
      CoreStatus.updateAvailable => Tokens.accent,
      CoreStatus.blocked => Tokens.danger,
      CoreStatus.notInstalled => Tokens.muted,
    };
    final label = switch (status) {
      CoreStatus.installed => 'installed',
      CoreStatus.notInstalled => 'not installed',
      CoreStatus.updateAvailable => 'update',
      CoreStatus.blocked => 'on hold',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: Tokens.body(size: 9, color: color)),
    );
  }
}

class _FlowBtn extends StatelessWidget {
  const _FlowBtn({
    required this.enabled,
    required this.icon,
    required this.onTap,
  });
  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: const Color(0xC90A0A0A),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x30DDE6F4)),
            ),
            child: Icon(icon, size: 20, color: Tokens.text),
          ),
        ),
      ),
    );
  }
}
