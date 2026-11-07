import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../state/save_sync.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_toast.dart';
import '../widgets/orbit_widgets.dart';
import 'game_detail_screen.dart' show saveName;
import 'launch.dart' show autoSlot;
import 'player_screen.dart';

/// Capsule — every save, one timeline (handoff §8.6, issue #149).
///
/// The screen renders only the content area: the rail, OS bar, backdrop and
/// hint row belong to the shell.
///
/// Layout families come from [Layout.ofSize]:
/// - desktop, tablet and tablet portrait keep the design's per-game rails:
///   a 66×88 cover and title beside a horizontal track of 168×96 snapshots;
/// - phone portrait turns the same saves into one vertical timeline across
///   games, newest first, with the track running down the left gutter.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.state});
  final AppState state;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  Future<List<_GameSaves>>? _future;
  String? _stamp;

  /// The snapshot whose card carries the focus halo. Null means the newest
  /// one, which is selected on arrival as in the design.
  String? _selected;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _stamp = _gameStamp;
    _future = _load();
  }

  String get _gameStamp =>
      state.games.map((g) => '${g.id}:${g.stateCount}').join('|');

  Future<List<_GameSaves>> _load() async {
    final out = <_GameSaves>[];
    for (final g in state.games) {
      final slots = await state.saves.list(g.id);
      if (slots.isEmpty) continue;
      slots.sort((a, b) => b.modified.compareTo(a.modified));
      out.add(_GameSaves(game: g, slots: slots));
    }
    out.sort((a, b) => b.newest.compareTo(a.newest));
    return out;
  }

  void _refresh() {
    _future = _load();
    if (mounted) setState(() {});
  }

  void _select(String key) {
    if (_selected == key) return;
    setState(() => _selected = key);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final layout = Layout.ofSize(media.size, media.orientation);
    final phone = Layout.isPhone(layout);
    final phonePortrait = layout == OrbitLayout.phonePortrait;
    final desktop = layout == OrbitLayout.desktop;

    // Handoff §10: phones hold the ×0.85 type scale; tablets and desktop
    // stay at ×1 with the compressed rhythm on short landscape windows.
    final scale = phone ? 0.85 : 1.0;
    // The header holds the design's 48 px gutter (104 + 48 = 152); the
    // timeline itself starts at 44 so its cover lands on the same 148 px
    // column as the rest of the destination headers.
    final side = phonePortrait
        ? 24.0
        : layout == OrbitLayout.phoneLandscape
        ? 20.0
        : 48.0;
    final railBodyInset = phonePortrait
        ? 16.0
        : layout == OrbitLayout.phoneLandscape
        ? 20.0
        : 44.0;
    final right = desktop ? 48.0 : side;
    final top = phonePortrait
        ? 24.0
        : Layout.isShort(layout)
        ? 18.0
        : 36.0;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (_stamp != _gameStamp) {
          _stamp = _gameStamp;
          _future = _load();
        }
        return FutureBuilder<List<_GameSaves>>(
          future: _future,
          builder: (context, snap) {
            final groups = snap.data ?? const <_GameSaves>[];
            final total = groups.fold<int>(
              0,
              (sum, g) =>
                  sum + g.slots.fold<int>(0, (s, slot) => s + slot.size),
            );
            final sizeLabel = _vaultSize(total, capacity: false);
            final meterSize = _vaultSize(total, capacity: true);
            final titleSize = phonePortrait
                ? 30.0
                : layout == OrbitLayout.phoneLandscape
                ? 26.0
                : layout == OrbitLayout.tablet
                ? 34.0
                : 44.0;
            final showEyebrow = !Layout.isShort(layout) || phonePortrait;
            final header = _Header(
              titleSize: titleSize,
              eyebrowSize: 13.0,
              showEyebrow: showEyebrow,
              compactMeter: phonePortrait,
              meterWidth: desktop
                  ? 320.0
                  : layout == OrbitLayout.tabletPortrait
                  ? 230.0
                  : phone
                  ? 250.0
                  : 260.0,
              vaultLabel: _vaultLabel,
              sizeLabel: sizeLabel,
              meterSize: meterSize,
            );

            final Widget body;
            if (snap.connectionState != ConnectionState.done) {
              body = const Center(
                child: CircularProgressIndicator(color: Tokens.accent),
              );
            } else if (groups.isEmpty) {
              body = _EmptyState(scale: scale, noGames: state.games.isEmpty);
            } else if (phonePortrait) {
              body = _VerticalTimeline(
                groups: groups,
                selected: _selected,
                onSelect: _select,
                onOpen: _open,
                onMenu: (g, s) => _menu(context, g, s),
              );
            } else {
              body = _RailsTimeline(
                groups: groups,
                selected: _selected,
                scale: scale,
                leftPad: railBodyInset,
                bottomPad: desktop
                    ? 70
                    : layout == OrbitLayout.phoneLandscape
                    ? 12
                    : 40,
                onSelect: _select,
                onOpen: _open,
                onMenu: (g, s) => _menu(context, g, s),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(side, top, right, 0),
                  child: header,
                ),
                SizedBox(
                  height: phonePortrait
                      ? 20
                      : Layout.isShort(layout)
                      ? 14
                      : desktop
                      ? 31
                      : 22,
                ),
                Expanded(child: body),
              ],
            );
          },
        );
      },
    );
  }

  String get _vaultLabel {
    final id = state.saves.id;
    if (id == 'local' || id == 'memory') return 'Local vault';
    return '${id[0].toUpperCase()}${id.substring(1)} vault';
  }

  /// The local vault's budget shown in the meter (design: 64 GB).
  static const _vaultCapacityGb = 64;

  /// Design copy: a one-decimal GB figure, with the vault budget in the
  /// desktop meter only; the phone header keeps the short form.
  static String _vaultSize(int bytes, {required bool capacity}) {
    if (bytes <= 0) return 'Empty';
    final used = bytes >= 1 << 30
        ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
        : fileSizeLabel(bytes);
    return capacity ? '$used of $_vaultCapacityGb GB' : used;
  }

  void _open(_GameSaves g, SaveSlot s) {
    _select(_slotKey(g.game.id, s.id));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PlayerScreen(gameId: g.game.id, state: state, initialSlot: s.id),
      ),
    );
  }

  void _menu(BuildContext context, _GameSaves g, SaveSlot s) {
    _select(_slotKey(g.game.id, s.id));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Tokens.text),
              title: Text('Resume and load snapshot', style: Tokens.body()),
              subtitle: Text(
                '${_slotLabel(s.id)} · kept locally only',
                style: Tokens.body(size: 11, color: Tokens.muted),
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                _open(g, s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Tokens.text),
              title: Text('Delete snapshot', style: Tokens.body()),
              subtitle: Text(
                '${_slotLabel(s.id)} · kept locally only',
                style: Tokens.body(size: 11, color: Tokens.muted),
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                _delete(context, g, s);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, _GameSaves g, SaveSlot s) async {
    final gameId = g.game.id;
    final bytes = await state.saves.download(gameId, s.id);
    await state.saves.remove(gameId, s.id);
    if (_selected == _slotKey(gameId, s.id)) _selected = null;
    await _syncCount(gameId);
    if (context.mounted) {
      showOrbitToast(
        context,
        message: 'Snapshot deleted',
        icon: Symbols.delete,
        iconColor: Tokens.text,
        onUndo: () async {
          if (bytes != null) {
            await state.saves.upload(gameId, s.id, bytes);
            await _syncCount(gameId);
            _refresh();
          }
        },
      );
    }
    _refresh();
  }

  Future<void> _syncCount(String gameId) async {
    try {
      final remaining = await state.saves.list(gameId);
      state.setStateCount(gameId, remaining.length);
    } catch (_) {
      // Count is display metadata; a listing failure must not break deletes.
    }
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _GameSaves {
  _GameSaves({required this.game, required this.slots});
  final GameEntry game;
  final List<SaveSlot> slots;
  DateTime get newest => slots.first.modified;
}

String _slotKey(String gameId, String slotId) => '$gameId\u0000$slotId';

/// The short pill on the snapshot artwork: the design's Auto / Slot /
/// Crash-safe tags, in the app's own slot vocabulary.
String _tag(SaveSlot s) {
  if (s.id == autoSlot) return 'Auto';
  if (s.id == 'crash-safe') return 'Crash-safe';
  if (s.id == 'slot0') return 'Quick save';
  final m = RegExp(r'^slot-(\d{2})(\d{2})(\d{2})$').firstMatch(s.id);
  if (m != null) return 'Slot ${m[1]}:${m[2]}';
  if (s.id.startsWith('slot ')) {
    return 'Slot ${s.id.substring(5)}';
  }
  return saveName(s.id);
}

/// The name of a slot in the timeline's subtitle.
String _slotLabel(String id) {
  if (id == autoSlot) return 'Autosave';
  if (id == 'crash-safe') return 'Crash-safe';
  if (id == 'slot0') return 'Quick save';
  final m = RegExp(r'^slot-(\d{2})(\d{2})(\d{2})$').firstMatch(id);
  if (m != null) return 'Saved ${m[1]}:${m[2]}';
  if (id.startsWith('slot ')) return 'Slot ${id.substring(5)}';
  return saveName(id);
}

/// The time under a snapshot: the design's "when you stopped" for the
/// automatic save, a short relative label otherwise.
String _when(SaveSlot s) =>
    s.id == autoSlot ? 'when you stopped' : _relative(s.modified);

String _relative(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = today.difference(day).inDays;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  if (days == 0) {
    final diff = now.difference(d);
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hr ago';
  }
  if (days == 1) return 'Yesterday $hh:$mm';
  if (days >= 7 && days < 14) return 'Last week';
  return lastPlayedLabel(d.millisecondsSinceEpoch);
}

/// The shorter, sentence-case time the phone timeline uses: "7 hr ago",
/// "yesterday", "2 days ago".
String _recent(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = today.difference(day).inDays;
  if (days <= 0) {
    final diff = now.difference(d);
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hr ago';
  }
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  final label = lastPlayedLabel(d.millisecondsSinceEpoch);
  if (label.isEmpty) return label;
  return label[0].toLowerCase() + label.substring(1);
}

/// The phone row's subtitle; a crash-safe save explains itself instead of
/// pretending to be a normal slot.
String _phoneSubtitle(SaveSlot s) {
  if (s.id == 'crash-safe') return 'Recovered after a crash';
  return '${_slotLabel(s.id)} · ${_recent(s.modified)}';
}

// ---------------------------------------------------------------------------
// Header and vault meter
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.titleSize,
    required this.eyebrowSize,
    required this.showEyebrow,
    required this.compactMeter,
    required this.meterWidth,
    required this.vaultLabel,
    required this.sizeLabel,
    required this.meterSize,
  });

  final double titleSize;
  final double eyebrowSize;
  final bool showEyebrow;
  final bool compactMeter;
  final double meterWidth;
  final String vaultLabel;
  final String sizeLabel;
  final String meterSize;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEyebrow) ...[
          Text(
            'EVERY SAVE. EVERY GAME.',
            style: Tokens.display(
              size: eyebrowSize,
              weight: FontWeight.w500,
              ls: 0.30 * eyebrowSize,
              height: 1,
              color: Tokens.muted,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Your time capsule',
          style: Tokens.display(
            size: titleSize,
            weight: FontWeight.w600,
            ls: -0.03 * titleSize,
            height: 1,
            color: Colors.white,
          ),
        ),
      ],
    );

    if (compactMeter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 9),
          Text(
            '$sizeLabel · kept on this device only',
            style: Tokens.body(size: 12.5, color: Tokens.muted, height: null),
          ),
        ],
      );
    }

    final meter = _VaultMeter(
      width: meterWidth,
      label: vaultLabel,
      sizeLabel: meterSize,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        const SizedBox(width: 24),
        Padding(
          padding: EdgeInsets.only(top: showEyebrow ? 12 : 2),
          child: meter,
        ),
      ],
    );
  }
}

class _VaultMeter extends StatelessWidget {
  const _VaultMeter({
    required this.width,
    required this.label,
    required this.sizeLabel,
  });

  final double width;
  final String label;
  final String sizeLabel;

  /// The prototype draws the fill at 22% as a decorative sample; the label
  /// carries the vault's real size.
  static const _fill = 0.22;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Tokens.body(
                    size: 13,
                    weight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
              Text(
                sizeLabel,
                style: Tokens.body(
                  size: 13,
                  weight: FontWeight.w600,
                  color: Tokens.muted,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: const Color(0x14DDE6F4),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _fill,
                heightFactor: 1,
                child: const ColoredBox(color: Tokens.accent),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Kept on this device only',
            style: Tokens.body(size: 12.5, color: Tokens.muted, height: 1),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-game rails (desktop, tablet, phone landscape)
// ---------------------------------------------------------------------------

class _RailsMetrics {
  _RailsMetrics(double scale)
    : rowHeight = 150 * (scale < 1 ? 0.87 : 1),
      rowGap = 18 * (scale < 1 ? 0.78 : 1),
      metaWidth = 230 * scale,
      metaGap = 20 * scale,
      coverWidth = 66 * scale,
      coverHeight = 88 * scale,
      coverGap = 14 * scale,
      cardWidth = 168 * scale,
      cardHeight = 96 * scale,
      cardRadius = 9 * (scale < 1 ? 0.9 : 1),
      cardGap = 22 * scale,
      trackTop = 118 * (scale < 1 ? 0.85 : 1),
      dotSize = 9 * (scale < 1 ? 0.9 : 1),
      dotTop = 10 * (scale < 1 ? 0.8 : 1),
      labelGap = 8 * (scale < 1 ? 0.8 : 1),
      tagHeight = 20 * (scale < 1 ? 0.9 : 1),
      tagInset = 7 * scale;

  final double rowHeight;
  final double rowGap;
  final double metaWidth;
  final double metaGap;
  final double coverWidth;
  final double coverHeight;
  final double coverGap;
  final double cardWidth;
  final double cardHeight;
  final double cardRadius;
  final double cardGap;
  final double trackTop;
  final double dotSize;
  final double dotTop;
  final double labelGap;
  final double tagHeight;
  final double tagInset;
}

class _RailsTimeline extends StatelessWidget {
  const _RailsTimeline({
    required this.groups,
    required this.selected,
    required this.scale,
    required this.leftPad,
    required this.bottomPad,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
  });

  final List<_GameSaves> groups;
  final String? selected;
  final double scale;
  final double leftPad;
  final double bottomPad;
  final ValueChanged<String> onSelect;
  final void Function(_GameSaves, SaveSlot) onOpen;
  final void Function(_GameSaves, SaveSlot) onMenu;

  @override
  Widget build(BuildContext context) {
    final m = _RailsMetrics(scale);
    final focusedRow = _focusedRow();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.88, 1],
        ).createShader(rect),
        child: ListView.separated(
          padding: EdgeInsets.only(top: 14, bottom: 24, left: leftPad),
          itemCount: groups.length,
          separatorBuilder: (_, _) => SizedBox(height: m.rowGap),
          itemBuilder: (context, i) {
            final g = groups[i];
            final faded = (i - focusedRow).abs() > 2;
            return AnimatedOpacity(
              duration: Tokens.ambientDur,
              curve: Tokens.ease,
              opacity: faded ? 0.3 : 1,
              child: SizedBox(
                height: m.rowHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: m.metaWidth,
                      child: _GameMeta(group: g, metrics: m, scale: scale),
                    ),
                    SizedBox(width: m.metaGap),
                    Expanded(
                      child: _SnapshotRail(
                        group: g,
                        groups: groups,
                        metrics: m,
                        selected: selected,
                        scale: scale,
                        onSelect: onSelect,
                        onOpen: onOpen,
                        onMenu: onMenu,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  int _focusedRow() {
    final key = selected;
    if (key == null) return 0;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].slots.any(
        (s) => _slotKey(groups[i].game.id, s.id) == key,
      )) {
        return i;
      }
    }
    return 0;
  }
}

class _GameMeta extends StatelessWidget {
  const _GameMeta({
    required this.group,
    required this.metrics,
    required this.scale,
  });

  final _GameSaves group;
  final _RailsMetrics metrics;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final count = group.slots.length;
    final system = systemLabel(group.game.system);
    return Row(
      children: [
        SizedBox(
          width: metrics.coverWidth,
          height: metrics.coverHeight,
          child: GameCover(
            gameId: group.game.id,
            title: group.game.title,
            systemId: group.game.system,
            radius: 5,
            dimmed: true,
          ),
        ),
        SizedBox(width: metrics.coverGap),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Tokens.display(
                  size: 17 * scale,
                  weight: FontWeight.w600,
                  ls: -0.2,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${countLabel(count, 'snapshot')} · $system',
                style: Tokens.body(
                  size: 13 * scale,
                  color: Tokens.muted,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SnapshotRail extends StatelessWidget {
  const _SnapshotRail({
    required this.group,
    required this.groups,
    required this.metrics,
    required this.selected,
    required this.scale,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
  });

  final _GameSaves group;
  final List<_GameSaves> groups;
  final _RailsMetrics metrics;
  final String? selected;
  final double scale;
  final ValueChanged<String> onSelect;
  final void Function(_GameSaves, SaveSlot) onOpen;
  final void Function(_GameSaves, SaveSlot) onMenu;

  bool get _firstOverall => identical(groups.first, group);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: metrics.trackTop,
          height: 1,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x993B8BFF), Color(0x1A3B8BFF)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < group.slots.length; i++) ...[
                  if (i > 0) SizedBox(width: metrics.cardGap),
                  _SnapshotCard(
                    group: group,
                    slot: group.slots[i],
                    metrics: metrics,
                    scale: scale,
                    focused: _isFocused(i),
                    onSelect: () =>
                        onSelect(_slotKey(group.game.id, group.slots[i].id)),
                    onOpen: () => onOpen(group, group.slots[i]),
                    onMenu: () => onMenu(group, group.slots[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _isFocused(int i) {
    final key = _slotKey(group.game.id, group.slots[i].id);
    if (selected != null) return selected == key;
    return _firstOverall && i == 0;
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.group,
    required this.slot,
    required this.metrics,
    required this.scale,
    required this.focused,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
  });

  final _GameSaves group;
  final SaveSlot slot;
  final _RailsMetrics metrics;
  final double scale;
  final bool focused;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(metrics.cardRadius);
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (hasFocus) {
        if (hasFocus) onSelect();
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onOpen();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => onSelect(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          onLongPress: onMenu,
          onSecondaryTap: onMenu,
          child: SizedBox(
            width: metrics.cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label:
                      '${_tag(slot)} snapshot · ${_when(slot)} · ${group.game.title}',
                  child: AnimatedContainer(
                    duration: Tokens.fastDur,
                    curve: Tokens.ease,
                    width: metrics.cardWidth,
                    height: metrics.cardHeight,
                    transformAlignment: Alignment.center,
                    transform: focused
                        ? (Matrix4.translationValues(0, -4, 0)
                            ..scaleByDouble(1.03, 1.03, 1, 1))
                        : null,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: focused ? Tokens.halo : null,
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _SnapshotArt(systemId: group.game.system),
                          if (_tag(slot).isNotEmpty)
                            Positioned(
                              left: metrics.tagInset,
                              top: metrics.tagInset,
                              child: _TagPill(
                                slot: slot,
                                height: metrics.tagHeight,
                                scale: scale,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 4, top: metrics.dotTop),
                  child: _Dot(
                    size: metrics.dotSize,
                    color: slot.id == 'crash-safe'
                        ? Tokens.warn
                        : const Color(0xFF3B8BFF),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: metrics.labelGap),
                  child: SizedBox(
                    width: metrics.cardWidth,
                    child: Text(
                      _when(slot),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: 12.5 * scale,
                        weight: FontWeight.w600,
                        color: Tokens.muted,
                        height: 1,
                      ),
                    ),
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

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.slot,
    required this.height,
    required this.scale,
  });

  final SaveSlot slot;
  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tag = _tag(slot);
    final color = slot.id == autoSlot
        ? Tokens.systemLabelFg
        : slot.id == 'crash-safe'
        ? Tokens.warn
        : Tokens.text;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 7 * scale),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xC7060B14),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontFamily: Tokens.bodyFamily,
          fontSize: 10.5 * scale,
          height: 1,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 10)],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vertical timeline (phone portrait)
// ---------------------------------------------------------------------------

class _VerticalTimeline extends StatelessWidget {
  const _VerticalTimeline({
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
  });

  final List<_GameSaves> groups;
  final String? selected;
  final ValueChanged<String> onSelect;
  final void Function(_GameSaves, SaveSlot) onOpen;
  final void Function(_GameSaves, SaveSlot) onMenu;

  static const _rowHeight = 110.0;
  static const _cardHeight = 96.0;
  static const _gutter = 46.0;

  List<_FlatSave> get _flat {
    final out = <_FlatSave>[
      for (final g in groups)
        for (final s in g.slots) _FlatSave(group: g, slot: s),
    ];
    out.sort((a, b) => b.slot.modified.compareTo(a.slot.modified));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = _flat;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final key = _slotKey(item.group.game.id, item.slot.id);
        final focused = selected == null ? i == 0 : selected == key;
        return _VerticalRow(
          item: item,
          first: i == 0,
          last: i == items.length - 1,
          focused: focused,
          onSelect: () => onSelect(key),
          onOpen: () => onOpen(item.group, item.slot),
          onMenu: () => onMenu(item.group, item.slot),
        );
      },
    );
  }
}

class _FlatSave {
  _FlatSave({required this.group, required this.slot});
  final _GameSaves group;
  final SaveSlot slot;
}

class _VerticalRow extends StatelessWidget {
  const _VerticalRow({
    required this.item,
    required this.first,
    required this.last,
    required this.focused,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
  });

  final _FlatSave item;
  final bool first;
  final bool last;
  final bool focused;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  static const _cardHeight = _VerticalTimeline._cardHeight;
  static const _gutter = _VerticalTimeline._gutter;
  static const _rowHeight = _VerticalTimeline._rowHeight;
  static const _dot = 9.0;

  @override
  Widget build(BuildContext context) {
    final slot = item.slot;
    final tag = _tag(slot);
    final color = slot.id == 'crash-safe'
        ? Tokens.warn
        : const Color(0xFF3B8BFF);
    final radius = BorderRadius.circular(14);
    final focusedFill = Color.alphaBlend(
      Tokens.text.withValues(alpha: 0.08),
      Tokens.bg,
    );
    const restFill = Color(0x09DDE6F4);

    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          SizedBox(
            width: _gutter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: _gutter / 2 - 0.5,
                  top: first ? _cardHeight / 2 : 0,
                  bottom: last ? _rowHeight - _cardHeight / 2 : 0,
                  child: Container(
                    width: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xB33B8BFF), Color(0x663B8BFF)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: _gutter / 2 - _dot / 2,
                  top: _cardHeight / 2 - _dot / 2,
                  child: _Dot(size: _dot, color: color),
                ),
              ],
            ),
          ),
          Expanded(
            child: FocusableActionDetector(
              mouseCursor: SystemMouseCursors.click,
              onFocusChange: (hasFocus) {
                if (hasFocus) onSelect();
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    onOpen();
                    return null;
                  },
                ),
              },
              child: MouseRegion(
                onEnter: (_) => onSelect(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  onLongPress: onMenu,
                  onSecondaryTap: onMenu,
                  child: AnimatedContainer(
                    duration: Tokens.fastDur,
                    curve: Tokens.ease,
                    height: _cardHeight,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: focused ? focusedFill : restFill,
                      borderRadius: radius,
                      border: Border.all(
                        color: focused ? Colors.transparent : Tokens.lineStrong,
                      ),
                      boxShadow: focused ? Tokens.halo : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          height: 76,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _SnapshotArt(systemId: item.group.game.system),
                                if (tag.isNotEmpty)
                                  Positioned(
                                    left: 8,
                                    top: 8,
                                    child: _TagPill(
                                      slot: slot,
                                      height: 20,
                                      scale: 1,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.group.game.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Tokens.display(
                                  size: 15.5,
                                  weight: FontWeight.w600,
                                  ls: -0.2,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _phoneSubtitle(slot),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Tokens.body(
                                  size: 12.5,
                                  color: Tokens.muted,
                                  height: null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snapshot artwork and empty state
// ---------------------------------------------------------------------------

/// The game's system-hue thumbnail: 45° bands at the design's two darker
/// shades (`oklch(0.37 .07 H)` / `oklch(0.31 .07 H)`).
class _SnapshotArt extends StatelessWidget {
  const _SnapshotArt({required this.systemId});
  final String systemId;

  @override
  Widget build(BuildContext context) {
    final hue = _snapshotHues[systemId] ?? 250.0;
    return CustomPaint(
      painter: _ThumbPainter(
        light: _oklch(0.37, 0.07, hue),
        dark: _oklch(0.31, 0.07, hue),
      ),
    );
  }
}

/// The design's system hue table (degrees), used for snapshot artwork.
const _snapshotHues = <String, double>{
  'nes': 25,
  'snes': 300,
  'n64': 150,
  'gb': 115,
  'gbc': 345,
  'gba': 270,
  'nds': 215,
  'psx': 245,
  'dc': 55,
  'psp': 190,
};

/// oklch → sRGB, so snapshot bands use the design's shades rather than a
/// per-channel darkening guess.
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
    return c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  }

  final r = gamma(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3);
  final g = gamma(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3);
  final bl = gamma(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3);
  return Color.fromARGB(
    255,
    (r * 255).round().clamp(0, 255),
    (g * 255).round().clamp(0, 255),
    (bl * 255).round().clamp(0, 255),
  );
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter({required this.light, required this.dark});
  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark);
    final paint = Paint()..color = light;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(math.pi / 4);
    final ext = size.width + size.height;
    for (var y = -ext; y <= ext; y += 16) {
      canvas.drawRect(Rect.fromLTWH(-ext, y, ext * 2, 8), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.light != light || old.dark != dark;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scale, required this.noGames});
  final double scale;
  final bool noGames;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No moments saved yet.',
              textAlign: TextAlign.center,
              style: Tokens.display(size: 22 * scale, height: 1.1),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                noGames
                    ? 'Import a game, play, then save a moment from the player.'
                    : 'Pause any game and choose “Save a moment” to pin it here.',
                textAlign: TextAlign.center,
                style: Tokens.body(size: 12, color: Tokens.muted, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
