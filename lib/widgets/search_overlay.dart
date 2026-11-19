import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_entry.dart';
import '../services/system_labels.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'library_looks/look_theme.dart' show listLastPlayedLabel;
import 'orbit_cover.dart' show OrbitCover;

/// The search overlay's own palette.
///
/// These are measured from the design render (§9, `library-search.md`). They
/// live with the widget because `theme/tokens.dart` is outside this task's
/// scope; every value is named here so no colour is repeated inline.
abstract final class _SearchColors {
  /// rgba(3,7,13,.9) — the full-screen scrim.
  static const scrim = Color(0xE603070D);
  static const field = Color(0xFF12161C);
  static const fieldBorder = Color(0xFF2F81F7);
  static const key = Color(0xFF1B212B);
  static const keyBorder = Color(0xFF262E3A);
  static const row = Color(0xFF141922);
  static const rowBorder = Color(0xFF232A35);
  static const eyebrow = Color(0xFF8A94A6);
  static const hint = Color(0xFF9AA4B2);
  static const pill = Color(0xFF1E242E);
  static const legend = Color(0xFFC7CEDB);
  static const caret = Color(0xFF2F81F7);
  static const clear = Color(0xFF8A94A6);
}

/// The on-screen key rows (§9): A–Z then 0–3 on the third row; 4–9, Space and
/// backspace make up the fourth row.
const _letterRows = <List<String>>[
  ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'],
  ['K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T'],
  ['U', 'V', 'W', 'X', 'Y', 'Z', '0', '1', '2', '3'],
];
const _dimmedKeys = <String>{'0', '1', '2', '3'};

/// Opens the full-screen search overlay and returns the game the player chose,
/// or null when it was dismissed. Pushing a route (rather than drawing inside
/// the library) lets the scrim cover the rail, OS bar and bottom nav exactly as
/// the reference render does, and restores the previous focus on the way out.
Future<GameEntry?> showSearchOverlay(
  BuildContext context, {
  required List<GameEntry> games,
  String initialQuery = '',
}) {
  return Navigator.of(context).push<GameEntry>(
    PageRouteBuilder<GameEntry>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Tokens.fastDur,
      reverseTransitionDuration: Tokens.fastDur,
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Tokens.ease),
        child: SearchOverlay(games: games, initialQuery: initialQuery),
      ),
    ),
  );
}

/// The search screen (§9, Devices 4c): a focused field, the on-screen keyboard
/// on large surfaces and a live list of recently played games or matches.
/// Phone portrait uses the system keyboard and shows the no-results card
/// instead of the grid, as the device reference does.
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({
    super.key,
    required this.games,
    this.initialQuery = '',
  });

  final List<GameEntry> games;
  final String initialQuery;

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay>
    with TickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  late final AnimationController _caret;
  String _query = '';
  String _activeKey = 'A';
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _controller = TextEditingController(text: _query);
    _focus = FocusNode(debugLabel: 'search overlay field');
    // A slow blink with a long visible phase: the caret reads as a steady
    // insertion point at a glance but still blinks as the design asks.
    _caret = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _caret.dispose();
    super.dispose();
  }

  void _close([GameEntry? game]) => Navigator.of(context).pop(game);

  void _setQuery(String value) {
    if (!mounted) return;
    setState(() {
      _query = value;
      _favoritesOnly = false;
      if (_controller.text != value) _controller.text = value;
    });
  }

  void _pressKey(String key) {
    if (key == 'backspace') {
      if (_query.isEmpty) return;
      _setQuery(_query.substring(0, _query.length - 1));
    } else {
      _setQuery('$_query${key == 'space' ? ' ' : key.toLowerCase()}');
    }
    setState(() => _activeKey = key);
    _focus.requestFocus();
  }

  /// Played games first, most recent at the top — the six rows in the empty
  /// reference render are exactly this order.
  List<GameEntry> get _recent {
    final played = widget.games.where((g) => g.lastPlayedMs > 0).toList()
      ..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    return played.take(6).toList();
  }

  List<GameEntry> get _matches {
    final q = _query.trim().toLowerCase();
    if (_favoritesOnly) {
      return widget.games.where((g) => g.favorite).toList()..sort(
        (a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs),
      );
    }
    if (q.isEmpty) return _recent;
    return widget.games.where((g) {
      return g.title.toLowerCase().contains(q) ||
          systemLabel(g.system).toLowerCase().contains(q) ||
          systemCode(g.system).toLowerCase().contains(q);
    }).toList()..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final layout = Layout.ofSize(size, MediaQuery.orientationOf(context));
    final phone = layout == OrbitLayout.phonePortrait;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => _close(),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focus.requestFocus(),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: const ColoredBox(color: _SearchColors.scrim),
                ),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, c) => phone
                      ? _phoneBody(c)
                      : _wideBody(c, layout),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Wide families (desktop, tablet, tablet portrait, phone landscape)
  // ---------------------------------------------------------------------

  Widget _wideBody(BoxConstraints c, OrbitLayout layout) {
    final railW = layout == OrbitLayout.phoneLandscape
        ? Tokens.railShort
        : Tokens.rail;
    final left = railW + 48.0;
    final right = 48.0;
    final availW = (c.maxWidth - left - right).clamp(360.0, double.infinity);
    final gridW = availW >= 1240 ? 600.0 : (availW - 46 - 360).clamp(320.0, 600.0);
    final resultsLeft = left + gridW + 43.0;
    final resultsW = (c.maxWidth - resultsLeft - right).clamp(280.0, double.infinity);

    return SingleChildScrollView(
      child: SizedBox(
        width: c.maxWidth,
        height: 900.0.clamp(c.maxHeight, double.infinity).toDouble(),
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: 84,
              child: Text(
                'FIND A GAME',
                style: Tokens.display(
                  size: 11,
                  weight: FontWeight.w600,
                  ls: 2.5,
                  color: _SearchColors.eyebrow,
                  height: null,
                ),
              ),
            ),
            Positioned(
              left: left,
              top: 120,
              child: SizedBox(
                width: availW,
                height: 78,
                child: _field(wide: true),
              ),
            ),
            Positioned(
              left: left,
              top: 236,
              child: SizedBox(
                width: gridW,
                height: 250,
                child: FittedBox(
                  alignment: Alignment.topLeft,
                  fit: BoxFit.scaleDown,
                  child: _keyGrid(),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: 509,
              child: Text(
                'Or type on any keyboard. Titles and systems both match, '
                'so “gba” works too.',
                style: Tokens.body(
                  size: 14,
                  color: _SearchColors.hint,
                  height: null,
                ),
              ),
            ),
            Positioned(
              left: resultsLeft,
              top: 226,
              width: resultsW,
              child: _results(wide: true),
            ),
            Positioned(
              right: right,
              bottom: 22,
              child: _legend(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({required bool wide}) {
    final radius = BorderRadius.circular(wide ? 16 : 12);
    final query = _controller.text;
    return AnimatedContainer(
      duration: Tokens.fastDur,
      curve: Tokens.ease,
      decoration: BoxDecoration(
        color: _SearchColors.field,
        borderRadius: radius,
        border: Border.all(color: _SearchColors.fieldBorder, width: 2),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          TextField(
            key: const Key('search-overlay-field'),
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            onChanged: _setQuery,
            style: Tokens.display(
              size: wide ? 32 : 17,
              weight: FontWeight.w600,
              color: Colors.white,
              ls: 0,
              height: null,
            ),
            cursorWidth: 0,
            showCursor: false,
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.only(
                left: wide ? 72 : 56,
                right: wide ? 24 : 56,
              ),
            ),
          ),
          Positioned(
            left: wide ? 32 : 16,
            child: Icon(
              Symbols.search,
              size: wide ? 20 : 18,
              color: _SearchColors.eyebrow,
            ),
          ),
          // The visible glyphs are drawn above the transparent-caret field so
          // the caret can sit directly after the text, as in the reference.
          Positioned(
            left: wide ? 72 : 56,
            right: wide ? 24 : 56,
            child: IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      query.isEmpty ? 'Type a title or a system' : query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.display(
                        size: wide ? 32 : 17,
                        weight: query.isEmpty ? FontWeight.w400 : FontWeight.w600,
                        ls: 0,
                        color: query.isEmpty
                            ? _SearchColors.eyebrow
                            : Colors.white,
                        height: null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedBuilder(
                    animation: _caret,
                    builder: (context, _) => Container(
                      width: wide ? 2 : 1.5,
                      height: wide ? 36 : 22,
                      color: _caret.value < 0.85
                          ? _SearchColors.caret
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!wide)
            Positioned(
              right: 8,
              child: GestureDetector(
                onTap: () => _setQuery(''),
                child: const Icon(
                  Symbols.close,
                  size: 14,
                  color: _SearchColors.clear,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _keyGrid() {
    return SizedBox(
      width: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in _letterRows) ...[
            _keyRow(row),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final k in const ['4', '5', '6', '7', '8', '9']) ...[
                _key(k, width: 54),
                const SizedBox(width: 6),
              ],
              _key('space', width: 112, label: 'Space'),
              const SizedBox(width: 6),
              _key('backspace', width: 108),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> row) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in row) ...[
          _key(k, width: 54),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _key(
    String key, {
    required double width,
    String? label,
  }) {
    final selected = key == _activeKey;
    final dimmed = _dimmedKeys.contains(key);
    return Semantics(
      button: true,
      label: key == 'backspace' ? 'Backspace' : (label ?? key),
      child: GestureDetector(
        onTap: () => _pressKey(key),
        child: Container(
          width: width,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _SearchColors.fieldBorder : _SearchColors.key,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? null
                : Border.all(color: _SearchColors.keyBorder),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x66007BFF),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: key == 'backspace'
              ? const Icon(Symbols.backspace, size: 20, color: Colors.white)
              : Text(
                  label ?? key,
                  style: Tokens.display(
                    size: key == 'space' ? 17 : 18,
                    weight: FontWeight.w600,
                    ls: 0,
                    color: dimmed ? _SearchColors.eyebrow : Colors.white,
                    height: null,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _legend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill('Enter'),
        const SizedBox(width: 6),
        Text(
          'Type',
          style: Tokens.body(
            size: 14,
            color: _SearchColors.legend,
            height: null,
          ),
        ),
        const SizedBox(width: 20),
        _pill('Esc'),
        const SizedBox(width: 6),
        Text(
          'Close',
          style: Tokens.body(
            size: 14,
            color: _SearchColors.legend,
            height: null,
          ),
        ),
      ],
    );
  }

  Widget _pill(String label) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _SearchColors.pill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Tokens.display(
          size: 12,
          weight: FontWeight.w600,
          color: Colors.white,
          ls: 0,
          height: null,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Results (both families)
  // ---------------------------------------------------------------------

  Widget _results({required bool wide}) {
    final matches = _matches;
    final querying = _favoritesOnly || _query.trim().isNotEmpty;
    final header = !querying
        ? 'RECENTLY PLAYED'
        : '${matches.length} ${matches.length == 1 ? 'MATCH' : 'MATCHES'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The phone reference goes straight from the field to the empty card.
        if (!(matches.isEmpty && !wide)) ...[
          Text(
            header,
            style: Tokens.display(
              size: wide ? 12 : 11,
              weight: FontWeight.w600,
              ls: 1.5,
              color: _SearchColors.eyebrow,
              height: null,
            ),
          ),
          const SizedBox(height: 15),
        ],
        if (matches.isEmpty)
          _noResults(wide: wide)
        else
          for (final game in matches) ...[
            _resultRow(game, wide: wide),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _resultRow(GameEntry game, {required bool wide}) {
    return Semantics(
      button: true,
      label: '${game.title}, ${systemLabel(game.system)}',
      child: GestureDetector(
        onTap: () => _close(game),
        child: Container(
          height: 72,
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: _SearchColors.row,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _SearchColors.rowBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 56,
                child: OrbitCover(
                  title: game.title,
                  systemId: game.system,
                  sysShort: systemCode(game.system),
                  year: game.year,
                  radius: 4,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      game.title,
                      key: Key('search-result-title-${game.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: wide ? 16 : 15,
                        weight: FontWeight.w600,
                        color: Colors.white,
                        height: null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${systemLabel(game.system)} · '
                      '${listLastPlayedLabel(game.lastPlayedMs)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tokens.body(
                        size: wide ? 13 : 12.5,
                        color: _SearchColors.hint,
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
    );
  }

  Widget _noResults({required bool wide}) {
    final q = _query;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 24 : 16,
        vertical: wide ? 28 : 24,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(wide ? 16 : 20),
        border: wide ? Border.all(color: _SearchColors.rowBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.searchOff,
            size: 34,
            color: _SearchColors.eyebrow,
          ),
          const SizedBox(height: 14),
          Text(
            'Nothing called “$q”',
            style: Tokens.display(
              size: 20,
              weight: FontWeight.w700,
              ls: 0,
              color: Colors.white,
              height: null,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Check the spelling, or search by system. Games you haven\'t '
            'added yet won\'t show up here.',
            style: Tokens.body(
              size: wide ? 14 : 13.5,
              color: _SearchColors.hint,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          if (_suggestedChips().isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in _suggestedChips())
                  _systemChip(chip.$1, chip.$2),
              ],
            ),
        ],
      ),
    );
  }

  /// The suggestions under the empty result: three systems from the
  /// collection in the design's order, then Favorites when there are any.
  List<(String, String)> _suggestedChips() {
    final present = {for (final g in widget.games) g.system};
    final out = <(String, String)>[];
    for (final id in const ['gba', 'snes', 'nds']) {
      if (present.contains(id)) out.add((systemCode(id), id));
    }
    if (widget.games.any((g) => g.favorite)) {
      out.add(('Favorites', '__favorites'));
    }
    return out;
  }

  Widget _systemChip(String label, String id) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () {
          if (id == '__favorites') {
            setState(() {
              _favoritesOnly = true;
              _controller.clear();
              _query = '';
            });
          } else {
            final labelForSystem = systemLabel(id);
            _controller.text = labelForSystem;
            _setQuery(labelForSystem);
          }
          _focus.requestFocus();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _SearchColors.key,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _SearchColors.keyBorder),
          ),
          child: Text(
            label,
            style: Tokens.body(
              size: 13,
              weight: FontWeight.w600,
              color: Tokens.text,
              height: null,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Phone portrait (Devices 4c)
  // ---------------------------------------------------------------------

  Widget _phoneBody(BoxConstraints c) {
    return SingleChildScrollView(
      child: SizedBox(
        width: c.maxWidth,
        height: c.maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.paddingOf(context).top + 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(height: 44, child: _field(wide: false)),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _close(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Cancel',
                        style: Tokens.body(
                          size: 14,
                          weight: FontWeight.w600,
                          color: Tokens.iconBlue,
                          height: null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _results(wide: false),
            ),
          ],
        ),
      ),
    );
  }
}
