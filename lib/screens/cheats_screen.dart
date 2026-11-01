import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cores/cheat_validators.dart';
import '../models/cheat.dart';
import '../models/core_manifest.dart';
import '../models/game_entry.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';

/// Cheats — Orbit §8.8.
///
/// Codes apply to the live session through [onCheatsChanged] when the game
/// is running (player), and at next boot otherwise. The screen renders only
/// the content area: the rail, OS bar, backdrop and hint row belong to the
/// shell.
///
/// Layout families come from [Layout.ofSize]:
/// - desktop, when the viewport can hold both columns: a 720-wide list with
///   the 440-wide code panel beside it;
/// - tablet, tablet portrait and phones: one column, ×0.85 type on phones,
///   with the code panel below the list.
class CheatsScreen extends StatefulWidget {
  const CheatsScreen({
    super.key,
    required this.gameId,
    required this.state,
    this.onCheatsChanged,
  });

  final String gameId;
  final AppState state;
  final Future<void> Function()? onCheatsChanged;

  @override
  State<CheatsScreen> createState() => _CheatsScreenState();
}

class _CheatsScreenState extends State<CheatsScreen> {
  /// Position in the cheat list whose code is shown in the panel. The first
  /// row is focused on arrival, as in the design.
  int _focused = 0;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final game = widget.state.games
            .where((g) => g.id == widget.gameId)
            .firstOrNull;
        if (game == null) {
          return const Scaffold(backgroundColor: Tokens.bg);
        }

        final core = _coreFor(game);
        final cheats = widget.state.cheatsFor(game.id);
        final families = core?.cheatFamilies ?? const <String>[];
        final media = MediaQuery.of(context);
        final layout = Layout.ofSize(media.size, media.orientation);
        final phone = Layout.isPhone(layout);
        final scale = phone ? 0.85 : 1.0;
        final focused = cheats.isEmpty
            ? 0
            : _focused.clamp(0, cheats.length - 1).toInt();

        return Scaffold(
          backgroundColor: Tokens.bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = !phone && c.maxWidth >= 1292;
                final side = wide ? 44.0 : (phone ? 20.0 : 32.0);
                final right = wide ? 48.0 : side;
                final top = wide ? 36.0 : (phone ? 28.0 : 32.0);
                final gap = c.maxWidth - side - right - 720 - 440;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(side, top, right, 32),
                  child: wide
                      ? _wide(
                          game: game,
                          core: core,
                          cheats: cheats,
                          families: families,
                          scale: scale,
                          focused: focused,
                          gap: gap,
                        )
                      : _narrow(
                          game: game,
                          core: core,
                          cheats: cheats,
                          families: families,
                          scale: scale,
                          focused: focused,
                          phone: phone,
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _wide({
    required GameEntry game,
    required CoreManifest? core,
    required List<CheatEntry> cheats,
    required List<String> families,
    required double scale,
    required int focused,
    required double gap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _header(game, phone: false),
        ),
        const SizedBox(height: 31),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 720,
              child: _listBody(
                game: game,
                core: core,
                cheats: cheats,
                families: families,
                scale: scale,
                focused: focused,
                phone: false,
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: 440,
              child: cheats.isEmpty
                  ? const SizedBox.shrink()
                  : _CodePanel(
                      cheat: cheats[focused],
                      families: families,
                      scale: scale,
                      width: double.infinity,
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _narrow({
    required GameEntry game,
    required CoreManifest? core,
    required List<CheatEntry> cheats,
    required List<String> families,
    required double scale,
    required int focused,
    required bool phone,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: phone ? 4 : 0),
          child: _header(game, phone: phone),
        ),
        SizedBox(height: phone ? 22 : 26),
        _listBody(
          game: game,
          core: core,
          cheats: cheats,
          families: families,
          scale: scale,
          focused: focused,
          phone: phone,
        ),
        if (cheats.isNotEmpty) ...[
          const SizedBox(height: 20),
          _CodePanel(
            cheat: cheats[focused],
            families: families,
            scale: scale,
            width: double.infinity,
          ),
        ],
      ],
    );
  }

  Widget _header(GameEntry game, {required bool phone}) {
    final titleSize = phone ? 28.0 : 44.0;
    final eyebrowSize = phone ? 12.0 : 13.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHEATS · ${systemLabel(game.system).toUpperCase()}',
          style: Tokens.display(
            size: eyebrowSize,
            weight: FontWeight.w500,
            ls: 0.30 * eyebrowSize,
            height: 1,
            color: Tokens.muted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          game.title,
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
  }

  Widget _listBody({
    required GameEntry game,
    required CoreManifest? core,
    required List<CheatEntry> cheats,
    required List<String> families,
    required double scale,
    required int focused,
    required bool phone,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (core == null || !core.cheatsSupported) ...[
          _notice(core, game),
          const SizedBox(height: 16),
        ],
        if (cheats.isEmpty)
          SizedBox(
            width: double.infinity,
            child: _emptyCard(families: families, scale: scale),
          )
        else ...[
          for (var i = 0; i < cheats.length; i++) ...[
            if (i > 0) SizedBox(height: 8 * scale),
            SizedBox(
              width: double.infinity,
              child: _CheatRow(
                key: ValueKey<int>(cheats[i].index),
                cheat: cheats[i],
                format: _formatFor(cheats[i].code, families),
                valid: _valid(cheats[i].code, families),
                focused: i == focused,
                autofocus: i == 0,
                scale: scale,
                onFocus: () => _focus(i),
                onToggle: () => _toggle(cheats[i].index),
                onDelete: () => _deleteCheat(cheats[i]),
              ),
            ),
          ],
          // The design's list column has gap 8 between children, and the
          // action row adds its own 12px top margin: 20 total.
          SizedBox(height: 20 * scale),
          _buttons(families: families, cheats: cheats, scale: scale),
        ],
      ],
    );
  }

  Widget _notice(CoreManifest? core, GameEntry game) {
    final text = core == null
        ? 'No installed core opens ${game.extension.toUpperCase()} files yet '
              '— codes are kept with the game and apply once a core is installed.'
        : 'This core exposes no cheat hooks — codes are kept with the game and '
              'apply if you switch to a core that supports them.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tokens.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Tokens.line),
      ),
      child: Text(
        text,
        style: Tokens.body(size: 12, color: Tokens.accent),
      ),
    );
  }

  Widget _buttons({
    required List<String> families,
    required List<CheatEntry> cheats,
    required double scale,
  }) {
    return Wrap(
      spacing: 10 * scale,
      runSpacing: 10 * scale,
      children: [
        _CheatButton(
          label: 'Import .cht file',
          icon: Symbols.uploadFile,
          scale: scale,
          onPressed: () => _importSheet(context),
        ),
        _CheatButton(
          label: 'Add a code',
          icon: Symbols.add,
          scale: scale,
          onPressed: () => _addSheet(context, families),
        ),
        _CheatButton(
          label: 'Export',
          icon: Symbols.iosShare,
          scale: scale,
          onPressed: cheats.isEmpty
              ? null
              : () => _exportSheet(context, cheats),
        ),
      ],
    );
  }

  Widget _emptyCard({
    required List<String> families,
    required double scale,
  }) {
    return _DashedBox(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24 * scale,
          vertical: 36 * scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Symbols.bolt, size: 40 * scale, color: Tokens.muted),
            SizedBox(height: 20 * scale),
            Text(
              'No cheats for this game',
              textAlign: TextAlign.center,
              style: Tokens.body(
                size: 19 * scale,
                weight: FontWeight.w700,
                height: 1.2,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8 * scale),
            Text(
              'Import a .cht file you have, or type a code.\n'
              'Nothing is looked up online.',
              textAlign: TextAlign.center,
              style: Tokens.body(
                size: 13 * scale,
                color: Tokens.muted,
                height: 1.55,
              ),
            ),
            SizedBox(height: 20 * scale),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _CheatButton(
                  label: 'Import file',
                  icon: Symbols.uploadFile,
                  primary: true,
                  scale: scale,
                  onPressed: () => _importSheet(context),
                ),
                _CheatButton(
                  label: 'Add a code',
                  icon: Symbols.add,
                  scale: scale,
                  onPressed: () => _addSheet(context, families),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  CoreManifest? _coreFor(GameEntry game) {
    final byId = widget.state.registry.catalog
        .where((m) => m.id == game.coreId)
        .firstOrNull;
    if (byId != null) return byId;
    final compatible = widget.state.registry.compatibleCores(game.extension);
    return compatible.isEmpty ? null : compatible.first;
  }

  void _focus(int index) {
    if (_focused != index) setState(() => _focused = index);
  }

  Future<void> _toggle(int index) async {
    widget.state.toggleCheat(widget.gameId, index);
    await widget.onCheatsChanged?.call();
  }

  Future<void> _deleteCheat(CheatEntry cheat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.panel,
        title: Text(
          'Delete ${cheat.desc}?',
          style: Tokens.display(size: 20, weight: FontWeight.w600, ls: -0.4),
        ),
        content: Text(
          'The code is removed from this game. This cannot be undone.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.state.deleteCheat(widget.gameId, cheat.index);
    await widget.onCheatsChanged?.call();
  }

  void _addSheet(BuildContext context, List<String>? families) {
    final name = TextEditingController();
    final code = TextEditingController();
    final available = (families != null && families.isNotEmpty)
        ? families
        : CheatValidators.families;
    var family = available.first;
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
              Text(
                'Add cheat',
                style: Tokens.display(
                  size: 18,
                  weight: FontWeight.w500,
                  ls: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: name,
                style: Tokens.body(size: 13),
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 8),
              OrbitSelect<String>(
                value: family,
                options: available.toList(),
                onChanged: (v) {
                  if (v != null) setSheet(() => family = v);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: code,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Code (one per line)',
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    error!,
                    style: Tokens.body(size: 12, color: Tokens.danger),
                  ),
                ),
              const SizedBox(height: 8),
              OrbitPrimary(
                label: 'Validate & save',
                icon: Symbols.check,
                expanded: true,
                onPressed: () async {
                  final problem = CheatValidators.validate(family, code.text);
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
            Text(
              'Paste .cht text to import',
              style: Tokens.display(
                size: 18,
                weight: FontWeight.w500,
                ls: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pasted,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            OrbitPrimary(
              label: 'Import',
              icon: Symbols.upload,
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
            Text(
              '.cht export (copy it somewhere safe)',
              style: Tokens.display(
                size: 16,
                weight: FontWeight.w500,
                ls: -0.4,
              ),
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
            OrbitPrimary(
              label: 'Copy',
              icon: Symbols.contentCopy,
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

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _CheatRow extends StatefulWidget {
  const _CheatRow({
    super.key,
    required this.cheat,
    required this.format,
    required this.valid,
    required this.focused,
    required this.autofocus,
    required this.scale,
    required this.onFocus,
    required this.onToggle,
    required this.onDelete,
  });

  final CheatEntry cheat;
  final String format;
  final bool valid;
  final bool focused;
  final bool autofocus;
  final double scale;
  final VoidCallback onFocus;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  State<_CheatRow> createState() => _CheatRowState();
}

class _CheatRowState extends State<_CheatRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  /// The design's `ez-shake`: 0 → −10 → 8 → −5 → 3 → 0 over 320 ms.
  double get _dx {
    final t = _shake.value;
    if (t < 0.2) return -10 * (t / 0.2);
    if (t < 0.4) return -10 + 18 * ((t - 0.2) / 0.2);
    if (t < 0.6) return 8 - 13 * ((t - 0.4) / 0.2);
    if (t < 0.8) return -5 + 8 * ((t - 0.6) / 0.2);
    return 3 - 3 * ((t - 0.8) / 0.2);
  }

  void _activate() {
    widget.onFocus();
    if (widget.valid) {
      widget.onToggle();
    } else {
      _shake.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.valid
        ? '${widget.format} · ${widget.cheat.enabled ? 'On' : 'Off'}'
        : 'Invalid code · can’t be turned on';
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (hasFocus) {
        if (hasFocus) widget.onFocus();
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) => Transform.translate(
          offset: Offset(_dx, 0),
          child: child,
        ),
        child: MouseRegion(
          onEnter: (_) => widget.onFocus(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            onLongPress: widget.onDelete,
            onSecondaryTap: widget.onDelete,
            child: Semantics(
              button: true,
              enabled: widget.valid,
              toggled: widget.cheat.enabled,
              label: widget.cheat.desc,
              child: AnimatedContainer(
                duration: Tokens.fastDur,
                curve: Tokens.ease,
                height: 80,
                padding: EdgeInsets.symmetric(horizontal: 24 * widget.scale),
                decoration: BoxDecoration(
                  // Opaque blend so the focus halo's spread shadows (which
                  // Flutter paints beneath the box, unlike CSS) cannot show
                  // through a translucent fill.
                  color: Color.alphaBlend(
                    Tokens.text.withValues(
                      alpha: widget.focused ? 0.10 : 0.035,
                    ),
                    // The focused row sits on the lighter nebula field in the
                    // design; the flat fallback keeps the same tint here.
                    widget.focused ? Tokens.spaceMid : Tokens.bg,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.focused
                        ? Colors.transparent
                        : Tokens.ringBorder.top.color,
                  ),
                  boxShadow: widget.focused ? Tokens.halo : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.cheat.desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tokens.body(
                              size: 17 * widget.scale,
                              weight: FontWeight.w700,
                              height: 1,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tokens.body(
                              size: 13.5 * widget.scale,
                              weight: FontWeight.w500,
                              height: 1,
                              color: widget.valid
                                  ? Tokens.muted
                                  : Tokens.dangerText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    _CheatToggle(
                      on: widget.cheat.enabled,
                      enabled: widget.valid,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheatToggle extends StatelessWidget {
  const _CheatToggle({required this.on, required this.enabled});

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: SizedBox(
        width: 56,
        height: 32,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: Tokens.fastDur,
                curve: Tokens.ease,
                decoration: BoxDecoration(
                  color: on ? Tokens.accent : Tokens.toggleOff,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              top: 4,
              left: on ? 28 : 4,
              width: 24,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? Colors.white : Tokens.toggleKnobOff,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 2),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Code panel
// ---------------------------------------------------------------------------

class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.cheat,
    required this.families,
    required this.scale,
    this.width,
  });

  final CheatEntry cheat;
  final List<String> families;
  final double scale;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final family = _familyFor(cheat.code, families);
    final rawError = family == null
        ? null
        : CheatValidators.validate(family, cheat.code);
    final error = rawError == null ? null : _friendlyError(rawError, family!);
    final lines = cheat.code.split('\n').length;
    final label = _formatFor(cheat.code, families);

    return Container(
      width: width,
      padding: EdgeInsets.all(24 * scale),
      decoration: BoxDecoration(
        // Recessed surface: the design's rgba(6,10,17,.5) over the nebula.
        color: Color.alphaBlend(
          Tokens.bg.withValues(alpha: 0.5),
          Tokens.spaceNebula,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Tokens.text.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Tokens.body(
                  size: 13 * scale,
                  weight: FontWeight.w600,
                  height: 1,
                  color: Tokens.muted,
                ),
              ),
              Text(
                '$lines lines',
                style: Tokens.body(
                  size: 13 * scale,
                  weight: FontWeight.w600,
                  height: 1,
                  color: Tokens.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            cheat.code,
            style: Tokens.mono(
              size: 17 * scale,
              height: 1.8,
              color: Tokens.text,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Tokens.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Tokens.danger.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Symbols.error,
                    size: 20,
                    color: Tokens.dangerText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error,
                      style: Tokens.body(
                        size: 14,
                        weight: FontWeight.w600,
                        height: 1.45,
                        color: Tokens.dangerText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons and empty card
// ---------------------------------------------------------------------------

class _CheatButton extends StatelessWidget {
  const _CheatButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.scale = 1,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final decoration = primary
        ? Tokens.primaryButton(
            state: enabled ? OrbitButtonState.rest : OrbitButtonState.disabled,
          )
        : Tokens.secondaryButton(
            state: enabled ? OrbitButtonState.rest : OrbitButtonState.disabled,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusPrimary),
        onTap: onPressed,
        child: Container(
          height: 52 * scale,
          padding: EdgeInsets.symmetric(horizontal: 20 * scale),
          decoration: decoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20 * scale, color: Colors.white),
              SizedBox(width: 10 * scale),
              Text(
                label,
                style: Tokens.body(
                  size: 15 * scale,
                  weight: FontWeight.w700,
                  height: null,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBox extends StatelessWidget {
  const _DashedBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: Tokens.text.withValues(alpha: 0.16),
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color});

  final Color color;

  static const double _radius = 16;
  static const double _dash = 5;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_radius),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Cheat-family helpers
// ---------------------------------------------------------------------------

const _familyLabels = <String, String>{
  'gb_gameshark': 'GameShark',
  'gb_gamegenie': 'Game Genie',
  'gba_actionreplay': 'Action Replay',
  'gba_codebreaker': 'CodeBreaker',
  'gba_gameshark': 'GameShark',
  'snes_gamegenie': 'Game Genie',
  'snes_proactionreplay': 'Pro Action Replay',
  'genesis_gamegenie': 'Game Genie',
  'genesis_actionreplay': 'Action Replay',
  'ps1_gameshark': 'GameShark',
  'saturn_gameshark': 'GameShark',
  'n64_gameshark': 'GameShark',
  'nes_gamegenie': 'Game Genie',
  'sms_actionreplay': 'Action Replay',
  'dc_codebreaker': 'CodeBreaker',
  'psp_cwcheat': 'CWCheat',
  'nds_actionreplay': 'Action Replay DS',
  'gc_gecko': 'Gecko',
};

String _familyLabel(String family) => _familyLabels[family] ?? family;

/// The family whose syntax accepts [code], else the first family, else null.
String? _familyFor(String code, List<String> families) {
  if (families.isEmpty) return null;
  for (final family in families) {
    if (CheatValidators.validate(family, code) == null) return family;
  }
  return families.first;
}

String _formatFor(String code, List<String> families) {
  final family = _familyFor(code, families);
  return family == null ? 'Cheat code' : _familyLabel(family);
}

bool _valid(String code, List<String> families) {
  if (families.isEmpty) return true;
  final family = _familyFor(code, families)!;
  return CheatValidators.validate(family, code) == null;
}

/// Turns the validator's machine wording into the panel's reader-facing
/// sentence, keeping the real line number.
String _friendlyError(String raw, String family) {
  final match = RegExp(r'^Line (\d+) ').firstMatch(raw);
  if (match == null) return raw;
  final label = _familyLabel(family).replaceAll(' DS', '');
  return 'Line ${match.group(1)} isn’t a valid $label code. '
      'Check for typos: codes use 0–9 and A–F.';
}
