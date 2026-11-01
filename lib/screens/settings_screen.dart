import 'dart:async';

import 'package:flutter/material.dart';

import '../brand/brand_mark.dart';
import '../emu/pcm_output.dart';
import '../services/gamepad.dart';
import '../services/pad_mapping.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../version.dart';
import '../widgets/collection_view.dart' show libraryViewKey;
import '../widgets/orbit_widgets.dart';

/// Settings — the six local-preference sections from the studio plate.
///
/// Desktop and tablets keep the vertical tab list; upright tablets wrap the
/// same tabs into pills above the rows, and phones drill into one section at a
/// time. Every preference is stored locally on this device.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state, this.initialTab});

  final AppState state;

  /// Opens straight into a section (used by tests and deep links).
  final String? initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// The six sections, in the order the design lists them.
const _tabs = <_SettingsTabData>[
  _SettingsTabData('Appearance', Symbols.palette),
  _SettingsTabData('Play', Symbols.playCircle),
  _SettingsTabData('Controls', Symbols.sportsEsports),
  _SettingsTabData('Audio', Symbols.volumeUp),
  _SettingsTabData('Storage', Symbols.folder),
  _SettingsTabData('About', Symbols.info),
];

class _SettingsTabData {
  const _SettingsTabData(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The five library looks the setting cycles through.
const _looks = <(String, String)>[
  ('3d', '3D shelf'),
  ('shelf', 'Shelf'),
  ('wall', 'Wall'),
  ('grid', 'Grid'),
  ('list', 'List'),
];

const _textSizes = <int>[100, 115, 130];

// Host bindings (not RetroPad inputs) have their own persisted keys.
const _quickSaveKey = 'quickSaveButton';
const _fastForwardKey = 'fastForwardButton';

class _SettingsScreenState extends State<SettingsScreen> {
  late String tab;

  /// Phone portrait: a section detail page, or null for the section list.
  String? _phoneSection;

  /// The row that carries the focus halo. The design focuses the first row.
  String _focusId = 'ap.look';

  /// False after a tab click (the row keeps its tint but not the halo).
  bool _haloOn = true;

  /// The row waiting for a controller button, if any.
  String? _listening;

  final _gamepads = GamepadService.shared;
  late final _padMap = PadMapping(widget.state);
  String? _padName;
  VoidCallback? _cancelPadConn;

  @override
  void initState() {
    super.initState();
    tab = widget.initialTab ?? 'Appearance';
    _phoneSection = widget.initialTab;
    _focusId = _firstRowId(tab);
    _cancelPadConn = _gamepads.onConnection((connected, name) {
      if (mounted) setState(() => _padName = connected ? name : null);
    });
  }

  @override
  void dispose() {
    _cancelPadConn?.call();
    super.dispose();
  }

  AppState get _state => widget.state;

  T _pref<T>(String key, T fallback) {
    final v = _state.settings[key];
    return v is T ? v : fallback;
  }

  Future<void> _set(String key, Object? value) => _state.setSetting(key, value);

  // ---- Appearance values -------------------------------------------------

  String get _lookValue {
    final raw = _state.settings[libraryViewKey];
    for (final (value, _) in _looks) {
      if (value == raw) return value;
    }
    return '3d';
  }

  String get _lookLabel {
    for (final (value, label) in _looks) {
      if (value == _lookValue) return label;
    }
    return _looks.first.$2;
  }

  int get _textSize {
    final raw = _state.settings['textScale'];
    final n = raw is num ? raw.toInt() : 100;
    return _textSizes.contains(n) ? n : 100;
  }

  double get _textScale => _textSize / 100;

  /// Follows the system until the person sets it here, as the copy promises.
  bool _reducedMotion(BuildContext context) {
    final raw = _state.settings['reduceMotion'];
    if (raw is bool) return raw;
    return MediaQuery.disableAnimationsOf(context);
  }

  // ---- Focus -------------------------------------------------------------

  String _firstRowId(String forTab) => switch (forTab) {
    'Appearance' => 'ap.look',
    'Play' => 'play.autosave',
    'Controls' => 'ctl.a',
    'Audio' => 'audio.mute',
    'Storage' => 'store.games',
    _ => 'about.version',
  };

  /// Phone Appearance leads with Text size, as the device frame does.
  String _phoneFirstRowId(String forTab) =>
      forTab == 'Appearance' ? 'ap.text' : _firstRowId(forTab);

  void _selectTab(String next) {
    setState(() {
      tab = next;
      _phoneSection = next;
      final phone = Layout.of(context) == OrbitLayout.phonePortrait;
      _focusId = phone ? _phoneFirstRowId(next) : _firstRowId(next);
      _haloOn = phone;
    });
  }

  // ---- Remapping ---------------------------------------------------------

  /// Waits for the next controller press and assigns it to [input].
  Future<void> _remapInput(String input, String label, String rowId) async {
    final picked = await _listenForButton(label, rowId);
    if (picked == null) return;
    await _padMap.assign(picked, input);
    if (mounted) {
      setState(() => _focusId = rowId);
      orbitToast(context, '$label is now on ${padButtonLabel(picked)}');
    }
  }

  /// Waits for the next controller press and stores it as a host binding.
  Future<void> _remapHost(String key, String label, String rowId) async {
    final picked = await _listenForButton(label, rowId);
    if (picked == null) return;
    await _set(key, picked);
    if (mounted) {
      setState(() => _focusId = rowId);
      orbitToast(context, '$label is now on ${padButtonLabel(picked)}');
    }
  }

  Future<String?> _listenForButton(String label, String rowId) async {
    setState(() {
      _listening = rowId;
      _focusId = rowId;
    });
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => _RemapSheet(
        label: label,
        padName: _padName,
        reduceMotion: _reducedMotion(context),
      ),
    );
    if (mounted) {
      setState(() {
        _listening = null;
      });
    }
    return picked;
  }

  String _hostButton(String key, String fallback) {
    final raw = _state.settings[key];
    return raw is String && padButtons.contains(raw) ? raw : fallback;
  }

  /// The design's value pills use the short controller names (RB, not
  /// "RB / R1"), while the button editor still spells them out.
  String _pillButtonLabel(String? button) => switch (button) {
    'lb' => 'LB',
    'rb' => 'RB',
    'lt' => 'LT',
    'rt' => 'RT',
    _ => padButtonLabel(button),
  };

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final scale = _textScale;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: _content(context),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final layout = Layout.of(context);
    final reduceMotion = _reducedMotion(context);

    switch (layout) {
      case OrbitLayout.phonePortrait:
        return _phonePortrait(context);
      case OrbitLayout.phoneLandscape:
        return _shortLandscape(context, reduceMotion);
      case OrbitLayout.tabletPortrait:
        return _pillsPortrait(context, reduceMotion);
      case OrbitLayout.tablet:
        return _tabbed(context, reduceMotion, short: true);
      case OrbitLayout.desktop:
        return _tabbed(context, reduceMotion, short: false);
    }
  }

  // ---- Wide layouts: header + vertical tabs + rows -----------------------

  Widget _tabbed(
    BuildContext context,
    bool reduceMotion, {
    required bool short,
  }) {
    final titleSize = short ? 32.0 : Tokens.screenTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          showEyebrow: !short,
          titleSize: titleSize,
          topPad: short ? 14 : 36,
        ),
        SizedBox(height: short ? 20 : 31),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 48, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final t in _tabs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _TabButton(
                            data: t,
                            active: tab == t.label,
                            reduceMotion: reduceMotion,
                            onTap: () => _selectTab(t.label),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 36),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _rowStack(tab, reduceMotion),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Tablet portrait: header + wrapping pills + rows -------------------

  Widget _pillsPortrait(BuildContext context, bool reduceMotion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(showEyebrow: true, titleSize: Tokens.screenTitle, topPad: 36),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(44, 0, 44, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _tabs)
                      _TabPill(
                        data: t,
                        active: tab == t.label,
                        reduceMotion: reduceMotion,
                        onTap: () => _selectTab(t.label),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _rowStack(tab, reduceMotion),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Phone landscape: short header + pills + rows ----------------------

  Widget _shortLandscape(BuildContext context, bool reduceMotion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(showEyebrow: false, titleSize: 22, topPad: 10),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in _tabs)
                      _TabPill(
                        data: t,
                        active: tab == t.label,
                        compact: true,
                        reduceMotion: reduceMotion,
                        onTap: () => _selectTab(t.label),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _rowStack(tab, reduceMotion),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Phone portrait: section list or one section ----------------------

  Widget _phonePortrait(BuildContext context) {
    final section = _phoneSection;
    if (section == null) return _phoneIndex();
    return _phoneDetail(section, _reducedMotion(context));
  }

  Widget _phoneIndex() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'STORED ON THIS DEVICE',
            style: Tokens.eyebrow.copyWith(color: Tokens.muted, height: 1),
          ),
          const SizedBox(height: 6),
          Text(
            'Settings',
            style: Tokens.display(
              size: 32,
              weight: FontWeight.w600,
              ls: -0.96,
              height: 1,
            ),
          ),
          const SizedBox(height: 18),
          for (final t in _tabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SectionTile(data: t, onTap: () => _selectTab(t.label)),
            ),
        ],
      ),
    );
  }

  Widget _phoneDetail(String section, bool reduceMotion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 18, 0),
          child: Row(
            children: [
              _CircleIconButton(
                icon: Symbols.arrowBack,
                tooltip: 'All settings',
                onTap: () => setState(() {
                  _phoneSection = null;
                  _listening = null;
                }),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.display(
                    size: 26,
                    weight: FontWeight.w600,
                    ls: -0.78,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: _rowStack(section, reduceMotion, compact: true),
          ),
        ),
      ],
    );
  }

  // ---- Shared header -----------------------------------------------------

  Widget _header({
    required bool showEyebrow,
    required double titleSize,
    required double topPad,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(48, topPad, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showEyebrow) ...[
            Text(
              'STORED ON THIS DEVICE',
              style: Tokens.eyebrow.copyWith(color: Tokens.muted, height: 1),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Settings',
            style: Tokens.display(
              size: titleSize,
              weight: FontWeight.w600,
              ls: -0.03 * titleSize,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Row stacks --------------------------------------------------------

  Widget _rowStack(String forTab, bool reduceMotion, {bool compact = false}) {
    final rows = <Widget>[];
    void add(Widget row) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(row);
    }

    switch (forTab) {
      case 'Appearance':
        final textRow = _row(
          id: 'ap.text',
          label: 'Text size',
          description: compact
              ? 'Applies everywhere. Layouts reflow; nothing gets cut off.'
              : 'Applies to every screen. Layouts reflow; nothing gets cut '
                    'off.',
          trailing: _ValuePill(value: '$_textSize%'),
          onTap: _cycleTextSize,
        );
        final lookRow = _row(
          id: 'ap.look',
          label: 'Library look',
          description: compact
              ? 'Same games, five ways to browse.'
              : '3D shelf, shelf rows, curved wall, grid or list. The V '
                    'button switches it from the library too.',
          trailing: _ValuePill(value: _lookLabel),
          onTap: _cycleLook,
        );
        final motionRow = _row(
          id: 'ap.motion',
          label: 'Reduce motion',
          description: compact
              ? 'Quick fades instead of 3D turns and zooms.'
              : 'Swaps 3D turns, zooms and parallax for quick fades. Follows '
                    'your system setting until you change it here.',
          trailing: _Toggle(
            value: _reducedMotion(context),
            label: 'Reduce motion',
            reduceMotion: reduceMotion,
            onChanged: (v) => _set('reduceMotion', v),
          ),
          onTap: () => _set('reduceMotion', !_reducedMotion(context)),
        );
        final ambientRow = _row(
          id: 'ap.ambient',
          label: 'Ambient motion',
          description: compact
              ? 'Stars drift; the room takes the selected game’s colour.'
              : 'Stars drift and the room picks up the colour of the '
                    'selected game.',
          trailing: _Toggle(
            value: _pref('motion', true),
            label: 'Ambient motion',
            reduceMotion: reduceMotion,
            onChanged: (v) => _set('motion', v),
          ),
          onTap: () => _set('motion', !_pref('motion', true)),
        );
        if (compact) {
          add(textRow);
          add(lookRow);
          add(motionRow);
          add(ambientRow);
        } else {
          add(lookRow);
          add(motionRow);
          add(ambientRow);
          add(textRow);
        }
        break;
      case 'Play':
        add(
          _row(
            id: 'play.autosave',
            label: 'Automatic snapshots',
            description:
                'Saves your place when you leave a game or switch apps, so '
                'Resume picks up where you stopped.',
            trailing: _Toggle(
              value: _pref('autosave', true),
              label: 'Automatic snapshots',
              reduceMotion: reduceMotion,
              onChanged: (v) => _set('autosave', v),
            ),
            onTap: () => _set('autosave', !_pref('autosave', true)),
          ),
        );
        add(
          _row(
            id: 'play.crash',
            label: 'Crash protection',
            description:
                'Runs each game’s core in a separate process, so a crashing '
                'core ends only that game. Experimental; desktop only.',
            trailing: _Toggle(
              value: _pref('crashContainment', false),
              label: 'Crash protection',
              reduceMotion: reduceMotion,
              onChanged: (v) => _set('crashContainment', v),
            ),
            onTap: () =>
                _set('crashContainment', !_pref('crashContainment', false)),
          ),
        );
        add(
          _row(
            id: 'play.ff',
            label: 'Fast-forward speed',
            description: 'How fast games run while fast-forward is on.',
            trailing: _ValuePill(value: '${_pref('ffFrames', '4')}× speed'),
            onTap: _cycleFastForward,
          ),
        );
        add(
          _row(
            id: 'play.verified',
            label: 'Core verification',
            description:
                'Every core file is checked against its published fingerprint '
                'before it runs.',
            trailing: _ValuePill(value: 'Always on', quiet: true),
          ),
        );
        add(
          _row(
            id: 'play.state',
            label: 'State format',
            description: 'Save states stay on this device.',
            trailing: _ValuePill(value: 'On this device', quiet: true),
          ),
        );
        add(
          _row(
            id: 'play.buttons',
            label: 'Controller buttons',
            description:
                'Every game button, the pause menu and the keyboard, in one '
                'place.',
            trailing: _ValuePill(value: 'Edit'),
            onTap: _openButtonEditor,
          ),
        );
        break;
      case 'Controls':
        add(_remapRow('ctl.a', 'Confirm', input: 'a'));
        add(_remapRow('ctl.b', 'Back', input: 'b'));
        add(
          _remapRow(
            'ctl.qs',
            'Quick save',
            hostKey: _quickSaveKey,
            fallback: 'rb',
          ),
        );
        add(
          _remapRow(
            'ctl.ff',
            'Fast-forward',
            hostKey: _fastForwardKey,
            fallback: 'rt',
          ),
        );
        // The phone design puts the touch overlay before haptics, because it
        // is the row a phone player changes most often.
        if (Layout.of(context) == OrbitLayout.phonePortrait) {
          add(
            _row(
              id: 'ctl.touch',
              label: 'On-screen controls',
              description: 'Hidden while a controller is connected',
              trailing: _Toggle(
                value: _pref('touchOverlay', true),
                label: 'On-screen controls',
                reduceMotion: reduceMotion,
                onChanged: (v) => _set('touchOverlay', v),
              ),
              onTap: () => _set('touchOverlay', !_pref('touchOverlay', true)),
            ),
          );
        }
        add(
          _row(
            id: 'ctl.haptics',
            label: 'Haptics',
            description:
                'Controller rumble for focus, launches, saves and errors.',
            trailing: _Toggle(
              value: _pref('haptics', true),
              label: 'Haptics',
              reduceMotion: reduceMotion,
              onChanged: (v) => _set('haptics', v),
            ),
            onTap: () => _set('haptics', !_pref('haptics', true)),
          ),
        );
        break;
      case 'Audio':
        add(
          _row(
            id: 'audio.mute',
            label: 'Mute all audio',
            description: 'Silences every game.',
            trailing: _Toggle(
              value: _pref('muted', false),
              label: 'Mute all audio',
              reduceMotion: reduceMotion,
              onChanged: (v) => _set('muted', v),
            ),
            onTap: () => _set('muted', !_pref('muted', false)),
          ),
        );
        add(
          _row(
            id: 'audio.volume',
            label: 'Game volume',
            description: 'Applies to all games.',
            trailing: _ValuePill(value: '${_pref('volume', '80')}%'),
            onTap: _cycleVolume,
          ),
        );
        add(
          _row(
            id: 'audio.output',
            label: 'Output',
            description:
                'The sound output ezCORE uses on this device. If there is '
                'none, the game tells you instead of going quiet.',
            trailing: _ValuePill(
              value: createPlatformPcm().sinkName.toUpperCase(),
              quiet: true,
            ),
          ),
        );
      case 'Storage':
        add(
          _row(
            id: 'store.games',
            label: 'Games folder',
            description:
                'Watched for new games when ezCORE opens. Add or scan folders '
                'from Add games.',
            trailing: _ValuePill(
              value: _state.romFolders.isEmpty
                  ? 'Not set'
                  : '${_state.romFolders.length} folder'
                        '${_state.romFolders.length == 1 ? '' : 's'}',
            ),
            onTap: _showGamesFolder,
          ),
        );
        add(
          _row(
            id: 'store.cores',
            label: 'Core directory',
            description:
                'Override for verified native cores. Empty = auto-detect.',
            trailing: _ValuePill(value: _coreDirectoryLabel(), quiet: true),
            onTap: _editCoreDirectory,
          ),
        );
        add(
          _row(
            id: 'store.policy',
            label: 'Content policy',
            description:
                'ezCORE ships no games, BIOS files or keys. You add the ones '
                'you own.',
            trailing: _ValuePill(value: 'Your files', quiet: true),
          ),
        );
        break;
      default:
        add(
          _row(
            id: 'about.version',
            label: 'Version',
            description: 'ezCORE frontend.',
            trailing: _ValuePill(value: appVersion),
          ),
        );
        add(
          _row(
            id: 'about.license',
            label: 'License',
            description: 'App shell.',
            trailing: _ValuePill(value: 'GPL-3.0-only'),
          ),
        );
        add(
          _row(
            id: 'about.cores',
            label: 'Cores',
            description: 'Each core keeps its upstream license.',
            trailing: _ValuePill(value: 'See manifest', quiet: true),
          ),
        );
        add(
          _row(
            id: 'about.dmca',
            label: 'DMCA',
            description: 'How rights holders reach the project.',
            trailing: _ValuePill(value: 'See DMCA.md', quiet: true),
          ),
        );
        add(
          _row(
            id: 'about.privacy',
            label: 'Privacy',
            description: 'No account, no telemetry, no network connections.',
            trailing: _ValuePill(value: 'Offline', quiet: true),
          ),
        );
        add(
          _row(
            id: 'about.reset',
            label: 'Reset appearance',
            description: 'Back to the defaults.',
            trailing: _ValuePill(value: 'Reset'),
            onTap: _resetAppearance,
          ),
        );
        add(_aboutCard());
        break;
    }

    return _RowMetrics(
      compact: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _row({
    required String id,
    required String label,
    required String description,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final focused = _focusId == id;
    return _OptionRow(
      label: label,
      description: description,
      trailing: trailing,
      focused: focused,
      halo: focused && _haloOn,
      onTap: onTap == null
          ? null
          : () {
              setState(() {
                _focusId = id;
                _haloOn = true;
              });
              onTap();
            },
      onHover: () {
        if (_focusId != id || !_haloOn) {
          setState(() {
            _focusId = id;
            _haloOn = true;
          });
        }
      },
    );
  }

  Widget _remapRow(
    String id,
    String label, {
    String? input,
    String? hostKey,
    String fallback = 'a',
  }) {
    final listening = _listening == id;
    final button = hostKey == null
        ? _padMap.buttonFor(input!)
        : _hostButton(hostKey, fallback);
    return _row(
      id: id,
      label: label,
      description: listening
          ? 'Press the button you want to use...'
          : 'Controller: ${_pillButtonLabel(button)}',
      trailing: _ValuePill(
        value: listening ? 'Listening' : _pillButtonLabel(button),
        listening: listening,
        reduceMotion: _reducedMotion(context),
      ),
      onTap: () {
        if (hostKey == null) {
          _remapInput(input!, label, id);
        } else {
          _remapHost(hostKey, label, id);
        }
      },
    );
  }

  // ---- Actions -----------------------------------------------------------

  void _cycleLook() {
    final i = _looks.indexWhere((l) => l.$1 == _lookValue);
    final next = _looks[(i + 1) % _looks.length].$1;
    _set(libraryViewKey, next);
  }

  void _cycleTextSize() {
    final i = _textSizes.indexOf(_textSize);
    _set('textScale', _textSizes[(i + 1) % _textSizes.length]);
  }

  void _cycleFastForward() {
    const speeds = ['2', '4', '8'];
    final current = _pref('ffFrames', '4');
    final i = speeds.indexOf(current);
    _set('ffFrames', speeds[(i + 1) % speeds.length]);
  }

  void _cycleVolume() {
    const levels = ['40', '60', '80', '100'];
    final current = _pref('volume', '80');
    final i = levels.indexOf(current);
    _set('volume', levels[(i + 1) % levels.length]);
  }

  Future<void> _resetAppearance() async {
    await _state.removeSetting('reduceMotion');
    await _state.removeSetting('textScale');
    await _state.removeSetting(libraryViewKey);
    await _set('motion', true);
    if (mounted) orbitToast(context, 'Appearance reset');
  }

  void _showGamesFolder() {
    final folders = _state.romFolders;
    orbitToast(
      context,
      folders.isEmpty
          ? 'No games folder yet. Add games to choose one.'
          : 'Watching ${folders.first}',
    );
  }

  String _coreDirectoryLabel() {
    final raw = _state.settings['coreDirectory'];
    if (raw is! String || raw.trim().isEmpty) return 'Auto';
    final path = raw.trim();
    return path.length <= 22 ? path : '…${path.substring(path.length - 21)}';
  }

  Future<void> _editCoreDirectory() async {
    final current = _pref('coreDirectory', '').toString();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _CoreDirectoryDialog(initial: current),
    );
    if (value == null) return;
    if (value.trim().isEmpty) {
      await _state.removeSetting('coreDirectory');
    } else {
      await _set('coreDirectory', value.trim());
    }
    if (mounted) orbitToast(context, 'Core directory updated');
  }

  Future<void> _openButtonEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ButtonEditorSheet(
        padMap: _padMap,
        padName: _padName,
        reduceMotion: _reducedMotion(context),
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _aboutCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _rowBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _rowRing),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLockup(height: 34),
          const SizedBox(height: 14),
          Text(
            Tokens.taglineMain,
            style: Tokens.body(size: 11, weight: FontWeight.w600, ls: 3.2),
          ),
          const SizedBox(height: 8),
          Text(
            'One app for every system. Pick a game and play; ezCORE picks the '
            'core. Open source, and every core is replaceable.',
            style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design components
// ---------------------------------------------------------------------------

const _rowBg = Color(0x09DDE6F4); // rgba(221,230,244,.035)
const _rowBgFocus = Color(0x1ADDE6F4); // rgba(221,230,244,.10)
const _rowRing = Color(0x24DDE6F4); // rgba(221,230,244,.14)
const _tabActiveBg = Color(0x29007BFF); // rgba(0,123,255,.16)
const _tabActiveRing = Color(0x73007BFF); // rgba(0,123,255,.45)
const _pillBg = Color(0x12DDE6F4); // rgba(221,230,244,.07)
const _pillRing = Color(0x26DDE6F4); // rgba(221,230,244,.15)

/// Phone rows run tighter so the value pill leaves the description room to
/// wrap to two lines instead of three.
class _RowMetrics extends InheritedWidget {
  const _RowMetrics({required this.compact, required super.child});
  final bool compact;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowMetrics>()?.compact ??
      false;

  @override
  bool updateShouldNotify(_RowMetrics oldWidget) =>
      compact != oldWidget.compact;
}

/// A settings option: label 17/700, description 14/500 and a control.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.description,
    required this.focused,
    required this.halo,
    this.trailing,
    this.onTap,
    this.onHover,
  });

  final String label;
  final String description;
  final Widget? trailing;
  final bool focused;
  final bool halo;
  final VoidCallback? onTap;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final compact = _RowMetrics.of(context);
    final surface = AnimatedContainer(
      duration: Tokens.fastDur,
      curve: Tokens.ease,
      constraints: const BoxConstraints(minHeight: 84),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 20 : 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: focused ? _rowBgFocus : _rowBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focused ? Colors.transparent : _rowRing),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Tokens.body(
                    size: 17,
                    weight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: compact ? 5 : 7),
                Text(
                  description,
                  style: Tokens.body(
                    size: compact ? 12 : 14,
                    color: Tokens.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: compact ? 10 : 24),
            trailing!,
          ],
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: label,
      child: MouseRegion(
        onEnter: (_) => onHover?.call(),
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // The halo is painted as rings, not as a filled shadow: the row
          // surface is translucent, and a solid shadow would show through it.
          child: halo
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _FocusHaloPainter()),
                      ),
                    ),
                    surface,
                  ],
                )
              : surface,
        ),
      ),
    );
  }
}

/// Draws the design's focus halo as a 2 px accent ring plus a 7 px glow ring,
/// so a translucent row never takes on the halo's fill.
class _FocusHaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final halo = RRect.fromRectAndRadius(
      Rect.fromLTWH(-7, -7, size.width + 14, size.height + 14),
      const Radius.circular(23),
    );

    final glowPaint = Paint()
      ..color = const Color(0x66007BFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..isAntiAlias = true;
    canvas.drawRRect(halo, glowPaint);

    final haloPaint = Paint()
      ..color = Tokens.focusHalo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..isAntiAlias = true;
    canvas.drawRRect(halo, haloPaint);

    final ringPaint = Paint()
      ..color = Tokens.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    final ring = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(15),
    );
    canvas.drawRRect(ring, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _FocusHaloPainter oldDelegate) => false;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.data,
    required this.active,
    required this.reduceMotion,
    required this.onTap,
  });

  final _SettingsTabData data;
  final bool active;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : Tokens.fastDur,
            curve: Tokens.ease,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: active ? _tabActiveBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? _tabActiveRing : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  data.icon,
                  size: 22,
                  weight: 400,
                  color: active ? Colors.white : Tokens.muted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 16,
                      weight: FontWeight.w600,
                      height: 1,
                      color: active ? Colors.white : Tokens.muted,
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

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.data,
    required this.active,
    required this.reduceMotion,
    required this.onTap,
    this.compact = false,
  });

  final _SettingsTabData data;
  final bool active;
  final bool reduceMotion;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : Tokens.fastDur,
          curve: Tokens.ease,
          height: compact ? 36 : 44,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          decoration: BoxDecoration(
            color: active ? _tabActiveBg : const Color(0x0DDDE6F4),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active ? _tabActiveRing : const Color(0x1FDDE6F4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                data.icon,
                size: compact ? 16 : 18,
                weight: 400,
                color: active ? Colors.white : Tokens.muted,
              ),
              SizedBox(width: compact ? 6 : 8),
              Text(
                data.label,
                style: Tokens.body(
                  size: compact ? 13 : 15,
                  weight: FontWeight.w600,
                  height: 1,
                  color: active ? Colors.white : Tokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.data, required this.onTap});
  final _SettingsTabData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: data.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _rowBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _rowRing),
          ),
          child: Row(
            children: [
              Icon(data.icon, size: 22, weight: 400, color: Tokens.muted),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  data.label,
                  style: Tokens.body(
                    size: 17,
                    weight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              const Icon(
                Symbols.chevronRight,
                size: 22,
                weight: 400,
                color: Tokens.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 26, weight: 400, color: Tokens.text),
          ),
        ),
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({
    required this.value,
    this.listening = false,
    this.quiet = false,
    this.reduceMotion = false,
  });

  final String value;

  /// Listening pills show the pulsing blue dot and accent text.
  final bool listening;

  /// Read-only status pills sit back a little.
  final bool quiet;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final compact = _RowMetrics.of(context);
    final pill = Container(
      constraints: const BoxConstraints(minWidth: 44),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pillBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pillRing),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // The pill is a fixed-size control: the text setting grows the row's
        // copy, not the control (the device frame keeps 56x32 toggles and
        // 32 px pills at 130%).
        textScaler: TextScaler.noScaling,
        style: Tokens.body(
          size: compact ? 14 : 15,
          weight: FontWeight.w700,
          height: 1,
          color: listening
              ? Tokens.iconBlue
              : quiet
              ? Tokens.muted
              : Tokens.text,
        ),
      ),
    );

    if (!listening) return pill;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PulsingDot(reduceMotion: reduceMotion),
        const SizedBox(width: 10),
        pill,
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({this.reduceMotion = false});
  final bool reduceMotion;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 1,
        end: 0.35,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Tokens.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.value,
    required this.label,
    required this.onChanged,
    required this.reduceMotion,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : Tokens.fastDur,
          curve: Tokens.ease,
          width: 56,
          height: 32,
          padding: const EdgeInsets.all(4),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? Tokens.accent : Tokens.toggleOff,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : Tokens.fastDur,
            curve: Tokens.ease,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: value ? Colors.white : Tokens.toggleKnobOff,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "listening" sheet: remapping takes over the bottom of the screen so it
/// is unmistakable that the app is waiting for a button, not a tap.
class _RemapSheet extends StatefulWidget {
  const _RemapSheet({
    required this.label,
    required this.padName,
    required this.reduceMotion,
  });

  final String label;
  final String? padName;
  final bool reduceMotion;

  @override
  State<_RemapSheet> createState() => _RemapSheetState();
}

class _RemapSheetState extends State<_RemapSheet> {
  Timer? _timeout;
  VoidCallback? _cancel;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 6), () {
      if (mounted) Navigator.of(context).pop();
    });
    _cancel = GamepadService.shared.onButton((e) {
      if (!e.pressed || !padButtons.contains(e.code)) return;
      _timeout?.cancel();
      if (mounted) Navigator.of(context).pop(e.code);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padName == null || widget.padName!.isEmpty
        ? 'your controller'
        : widget.padName!;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16202F), Color(0xFF0A0F18)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Tokens.lineStrong)),
          boxShadow: [
            BoxShadow(
              color: Color(0x99000000),
              offset: Offset(0, -18),
              blurRadius: 60,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0x33DDE6F4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 100,
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A1A2E),
                border: Border.all(color: Tokens.accent, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40007BFF),
                    blurRadius: 34,
                    spreadRadius: -4,
                  ),
                ],
                gradient: const RadialGradient(
                  colors: [Color(0x40007BFF), Color(0x000A1A2E)],
                ),
              ),
              child: const Icon(
                Symbols.sportsEsports,
                size: 40,
                weight: 400,
                fill: 1,
                color: Tokens.text,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Press a button for ${widget.label}',
              textAlign: TextAlign.center,
              style: Tokens.display(
                size: 23,
                weight: FontWeight.w600,
                ls: -0.69,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Listening on $pad. Cancels in 6 s if nothing is pressed.',
                textAlign: TextAlign.center,
                style: Tokens.body(size: 15, color: Tokens.muted, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every game-button assignment, plus the controller and keyboard facts that
/// used to live in the Controls section. Kept out of the main list so the
/// four most-used bindings stay the focus.
class _ButtonEditorSheet extends StatefulWidget {
  const _ButtonEditorSheet({
    required this.padMap,
    required this.padName,
    required this.reduceMotion,
    required this.onChanged,
  });

  final PadMapping padMap;
  final String? padName;
  final bool reduceMotion;
  final VoidCallback onChanged;

  @override
  State<_ButtonEditorSheet> createState() => _ButtonEditorSheetState();
}

class _ButtonEditorSheetState extends State<_ButtonEditorSheet> {
  static const _inputs = <(String, String)>[
    ('a', 'A'),
    ('b', 'B'),
    ('x', 'X'),
    ('y', 'Y'),
    ('l', 'L / L1'),
    ('r', 'R / R1'),
    ('l2', 'L2 / Z'),
    ('r2', 'R2'),
    ('l3', 'L3'),
    ('r3', 'R3'),
    ('select', 'Select'),
    ('start', 'Start'),
    ('up', 'Up'),
    ('down', 'Down'),
    ('left', 'Left'),
    ('right', 'Right'),
  ];

  String? _listening;

  Future<void> _listen(String input, String label) async {
    setState(() => _listening = input);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => _RemapSheet(
        label: label,
        padName: widget.padName,
        reduceMotion: widget.reduceMotion,
      ),
    );
    if (!mounted) return;
    setState(() => _listening = null);
    if (picked != null) {
      await widget.padMap.assign(picked, input);
      if (mounted) setState(() {});
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.82,
        decoration: const BoxDecoration(
          color: Color(0xFF0B111B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Tokens.lineStrong)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0x33DDE6F4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Buttons',
              style: Tokens.display(
                size: 24,
                weight: FontWeight.w600,
                ls: -0.72,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose which controller button presses each game button.',
              style: Tokens.body(size: 13, color: Tokens.muted),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: _inputs.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  if (i == _inputs.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pause menu: hold Select and Start together. '
                              'Keyboard: arrows move, Z = B, X = A, A = Y, '
                              'S = X, Q = L, W = R, Right Shift = Select, '
                              'Enter = Start, Esc = pause menu.',
                              style: Tokens.body(
                                size: 12,
                                color: Tokens.muted,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final (input, label) = _inputs[i];
                  final listening = _listening == input;
                  final button = widget.padMap.buttonFor(input);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _listen(input, label),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _rowBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _rowRing),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  style: Tokens.body(
                                    size: 15,
                                    weight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  listening
                                      ? 'Press the button you want to use...'
                                      : 'Controller: '
                                            '${padButtonLabel(button)}',
                                  style: Tokens.body(
                                    size: 12,
                                    color: Tokens.muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          _ValuePill(
                            value: listening
                                ? 'Listening'
                                : padButtonLabel(button),
                            listening: listening,
                            reduceMotion: widget.reduceMotion,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _rowBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _rowRing),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'On-screen controls',
                          style: Tokens.body(
                            size: 15,
                            weight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hidden while a controller is connected',
                          style: Tokens.body(
                            size: 12,
                            color: Tokens.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _Toggle(
                    value:
                        widget.padMap.state.settings['touchOverlay'] != false,
                    label: 'On-screen controls',
                    reduceMotion: widget.reduceMotion,
                    onChanged: (v) async {
                      await widget.padMap.state.setSetting('touchOverlay', v);
                      if (mounted) setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.padName == null
                        ? 'No controller detected.'
                        : 'Controller: ${widget.padName}',
                    style: Tokens.body(size: 12, color: Tokens.muted),
                  ),
                ),
                OrbitSecondary(
                  label: 'Reset to default',
                  onPressed: widget.padMap.isDefault
                      ? null
                      : () async {
                          await widget.padMap.reset();
                          if (mounted) setState(() {});
                          widget.onChanged();
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoreDirectoryDialog extends StatefulWidget {
  const _CoreDirectoryDialog({required this.initial});
  final String initial;

  @override
  State<_CoreDirectoryDialog> createState() => _CoreDirectoryDialogState();
}

class _CoreDirectoryDialogState extends State<_CoreDirectoryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Tokens.dockTop,
      title: Text(
        'Core directory',
        style: Tokens.display(size: 22, weight: FontWeight.w600, ls: -0.6),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Override for verified native cores. Leave empty to auto-detect.',
            style: Tokens.body(size: 13, color: Tokens.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: Tokens.body(size: 14),
            decoration: const InputDecoration(hintText: 'Auto-detect'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: Tokens.body(size: 14, color: Tokens.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('Save', style: Tokens.body(size: 14)),
        ),
      ],
    );
  }
}
