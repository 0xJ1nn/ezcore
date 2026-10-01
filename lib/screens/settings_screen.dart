import 'package:flutter/material.dart';

import '../emu/pcm_output.dart';
import '../services/gamepad.dart';
import '../services/pad_mapping.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../version.dart';
import '../widgets/orbit_widgets.dart';

/// Orbit Settings — 6 local-preference tabs (final-01).
/// Appearance / Emulation / Controllers / Audio / Library & storage / About.
/// All controls persist into [AppState.settings]; nothing leaves the device.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    this.onGoVault,
    this.initialTab,
  });
  final AppState state;
  final VoidCallback? onGoVault;
  final String? initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String tab;
  final _gamepads = GamepadService.shared;
  String? _padName;
  VoidCallback? _cancelPadConn;

  @override
  void initState() {
    super.initState();
    tab = widget.initialTab ?? 'Appearance';
    _cancelPadConn = _gamepads.onConnection((connected, name) {
      if (mounted) setState(() => _padName = connected ? name : null);
    });
  }

  @override
  void dispose() {
    _cancelPadConn?.call();
    super.dispose();
  }

  static const tabs = [
    ('Appearance', Icons.auto_awesome_outlined),
    ('Emulation', Icons.sports_esports_outlined),
    ('Controllers', Icons.gamepad_outlined),
    ('Audio', Icons.volume_up_outlined),
    ('Library & storage', Icons.folder_outlined),
    ('About ezCORE', Icons.info_outline),
  ];

  T _pref<T>(String key, T fallback) {
    final v = widget.state.settings[key];
    return v is T ? v : fallback;
  }

  Future<void> _set(String key, Object? value) =>
      widget.state.setSetting(key, value);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final layout = Layout.of(context);
    final portrait = Layout.isPortrait(layout);
    final compact = layout == OrbitLayout.phoneLandscape;
    final useTabs = portrait || compact;
    final short = Layout.isShort(layout);
    final osPad = Tokens.osPad(size.width, portrait: portrait, short_: short);
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final nav = _nav(useTabs);
        final panel = _panel();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(osPad, short ? 10 : 26, osPad, 0),
              child: Text(
                'Settings',
                style: Tokens.display(
                  size: short ? 22 : (portrait ? 24 : 28),
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  osPad,
                  short ? 12 : 32,
                  osPad,
                  short ? 8 : 24,
                ),
                child: useTabs
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: nav,
                          ),
                          const SizedBox(height: 22),
                          Expanded(child: SingleChildScrollView(child: panel)),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 170, child: nav),
                          SizedBox(width: short ? 18 : 48),
                          Expanded(child: SingleChildScrollView(child: panel)),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _nav(bool portrait) {
    return portrait
        ? Row(
            children: [
              for (final (label, icon) in tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NavBtn(
                    label: label,
                    icon: icon,
                    active: tab == label,
                    onTap: () => setState(() => tab = label),
                  ),
                ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (label, icon) in tabs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _NavBtn(
                    label: label,
                    icon: icon,
                    active: tab == label,
                    onTap: () => setState(() => tab = label),
                  ),
                ),
            ],
          );
  }

  Widget _panel() {
    return switch (tab) {
      'Appearance' => _appearance(),
      'Emulation' => _emulation(),
      'Controllers' => _controllers(),
      'Audio' => _audio(),
      'Library & storage' => _library(),
      _ => _about(),
    };
  }

  Widget _appearance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appearance',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 16),
        _row(
          'Ambient motion',
          'Drifting stars behind the library. Turn off for a still '
              'background.',
          OrbitToggle(
            label: 'Ambient motion',
            value: _pref('motion', true),
            onChanged: (v) => _set('motion', v),
          ),
        ),
        _row(
          'Reset',
          'Back to the defaults.',
          OrbitSecondary(
            label: 'Reset appearance',
            onPressed: () async {
              await _set('motion', true);
              if (mounted) {
                orbitToast(context, 'Appearance reset');
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _emulation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emulation',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Applies to every game.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'Automatic snapshots',
          'Saves your place when you leave a game or switch apps, so Resume '
              'picks up where you stopped.',
          OrbitToggle(
            label: 'Automatic snapshots',
            value: _pref('autosave', true),
            onChanged: (v) => _set('autosave', v),
          ),
        ),
        _row(
          'Crash protection',
          'Runs each game\'s core in a separate process, so a crashing core '
              'ends only that game. Experimental; desktop only.',
          OrbitToggle(
            label: 'Crash protection',
            value: _pref('crashContainment', false),
            onChanged: (v) => _set('crashContainment', v),
          ),
        ),
        _row(
          'Fast-forward speed',
          'How fast games run while fast-forward is on.',
          OrbitSelect<String>(
            value: _pref('ffFrames', '4'),
            options: const ['2', '4', '8'],
            labels: const {'2': '2× speed', '4': '4× speed', '8': '8× speed'},
            onChanged: (v) => _set('ffFrames', v ?? '4'),
          ),
        ),
        _row(
          'Core verification',
          'Every core file is checked against its published fingerprint '
              'before it runs.',
          Text(
            'ALWAYS ON',
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
        _row(
          'State format',
          'Save states stay on this device.',
          Text(
            'ON THIS DEVICE',
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
      ],
    );
  }

  late final _padMap = PadMapping(widget.state);

  /// Waits for the next controller press and gives it [input].
  Future<void> _remap(String input, String label) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _PressAButtonDialog(label: label),
    );
    if (picked == null) return;
    await _padMap.assign(picked, input);
    if (mounted) {
      setState(() {});
      orbitToast(context, '$label is now on ${padButtonLabel(picked)}');
    }
  }

  Widget _controllers() {
    const inputs = [
      ('a', 'A'), ('b', 'B'), ('x', 'X'), ('y', 'Y'),
      ('l', 'L / L1'), ('r', 'R / R1'), ('l2', 'L2 / Z'), ('r2', 'R2'),
      ('l3', 'L3'), ('r3', 'R3'), ('select', 'Select'), ('start', 'Start'),
      ('up', 'Up'), ('down', 'Down'), ('left', 'Left'), ('right', 'Right'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Controllers',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 16),
        _row(
          'Controller',
          _padName == null
              ? 'No controller detected. Connect one to play without touch.'
              : 'Connected: $_padName.',
          Text(
            _padName == null ? 'NONE' : 'READY',
            style: Tokens.body(
              size: 9,
              ls: 1.0,
              color: _padName == null ? Tokens.muted : Tokens.ok,
            ),
          ),
        ),
        _row(
          'Pause menu',
          'Hold Select and Start together during a game.',
          Text('SELECT + START',
              style: Tokens.body(size: 12, color: Tokens.muted)),
        ),
        _row(
          'Menus',
          'The d-pad moves, A chooses, B goes back.',
          Text('D-PAD  A  B', style: Tokens.body(size: 12, color: Tokens.muted)),
        ),
        const SizedBox(height: 12),
        Text('Buttons', style: Tokens.display(size: 18, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Choose which controller button presses each game button.',
          style: Tokens.body(size: 12, color: Tokens.muted),
        ),
        for (final (input, label) in inputs)
          _row(
            label,
            'Controller: ${padButtonLabel(_padMap.buttonFor(input))}',
            OrbitSecondary(
              label: 'Change',
              onPressed: () => _remap(input, label),
            ),
          ),
        _row(
          'Reset buttons',
          _padMap.isDefault
              ? 'Using the default layout.'
              : 'Back to the default layout.',
          OrbitSecondary(
            label: 'Reset to default',
            onPressed: _padMap.isDefault
                ? null
                : () async {
                    await _padMap.reset();
                    if (mounted) setState(() {});
                  },
          ),
        ),
        _row(
          'Keyboard',
          'Arrows move. Z = B, X = A, A = Y, S = X, Q = L, W = R, '
              'Right Shift = Select, Enter = Start, Esc = pause menu. In DOS '
              'and other keyboard games every key goes to the game and F12 '
              'opens the menu.',
          const SizedBox.shrink(),
        ),
        _row(
          'On-screen controls',
          'Show touch controls in games. Customise them from the pause menu.',
          OrbitToggle(
            label: 'On-screen controls',
            value: _pref('touchOverlay', true),
            onChanged: (v) => _set('touchOverlay', v),
          ),
        ),
        _row(
          'Haptics',
          'A light tap confirms touch-pad presses.',
          OrbitToggle(
            label: 'Haptics',
            value: _pref('haptics', true),
            onChanged: (v) => _set('haptics', v),
          ),
        ),
      ],
    );
  }

  Widget _audio() {
    final vol = _pref('volume', '80');
    final volD = double.tryParse(vol) ?? 80;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audio',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Changes apply the next time a game starts.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'Volume',
          'Scales the emulated stereo signal, 0–100.',
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Tokens.accent,
                      inactiveTrackColor: const Color(0xFF1C3350),
                      thumbColor: Tokens.accent,
                      overlayColor: Tokens.accent.withValues(alpha: 0.15),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                    ),
                    child: Slider(
                      value: volD.clamp(0, 100),
                      min: 0,
                      max: 100,
                      onChanged: (v) => _set('volume', v.round().toString()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$vol%',
                  style: Tokens.body(size: 11, color: Tokens.muted),
                ),
              ],
            ),
          ),
        ),
        _row(
          'Mute all audio',
          'Silences every game.',
          OrbitToggle(
            label: 'Mute all audio',
            value: _pref('muted', false),
            onChanged: (v) => _set('muted', v),
          ),
        ),
        _row(
          'Output',
          'The sound output ezCORE uses on this device. If there is none, the '
              'game tells you instead of going quiet.',
          Text(
            createPlatformPcm().sinkName.toUpperCase(),
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
      ],
    );
  }

  Widget _library() {
    final dirCtrl = TextEditingController(
      text: _pref('coreDirectory', '').toString(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Library & storage',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Your games and saves never leave this device.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'Core directory',
          'Override for verified native cores. Empty = auto-detect.',
          SizedBox(
            width: 260,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: dirCtrl,
                    style: Tokens.body(size: 12),
                    decoration: const InputDecoration(hintText: 'Auto-detect'),
                  ),
                ),
                const SizedBox(width: 8),
                OrbitSecondary(
                  label: 'Save',
                  onPressed: () async {
                    final v = dirCtrl.text.trim();
                    if (v.isEmpty) {
                      await widget.state.removeSetting('coreDirectory');
                    } else {
                      await _set('coreDirectory', v);
                    }
                    if (mounted) {
                      orbitToast(context, 'Core directory updated');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        _row(
          'Saves',
          'Every save state, for every game.',
          OrbitSecondary(
            label: 'Open saves',
            onPressed: () => widget.onGoVault?.call(),
          ),
        ),
        _row(
          'Content policy',
          'ezCORE ships no games, BIOS files or keys. You add the ones you '
              'own.',
          Text(
            'YOUR FILES',
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
      ],
    );
  }

  Widget _about() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ezCORE',
          style: Tokens.display(size: 26, weight: FontWeight.w700, ls: -1.0),
        ),
        const SizedBox(height: 8),
        Text(
          'One app for every system. Pick a game and play; ezCORE picks the '
              'core.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'License',
          'App shell.',
          Text('GPL-3.0-only', style: Tokens.body(size: 11)),
        ),
        _row(
          'Cores',
          'Each core keeps its upstream license.',
          Text(
            'See manifest',
            style: Tokens.body(size: 11, color: Tokens.muted),
          ),
        ),
        _row(
          'DMCA',
          'How rights holders reach the project.',
          Text('See DMCA.md', style: Tokens.body(size: 11)),
        ),
        _row(
          'Version',
          'This build.',
          Text(appVersion, style: Tokens.body(size: 11)),
        ),
        _notice(
          text:
              'Open source. Emulators run as replaceable cores you can add and '
              'remove.',
        ),
      ],
    );
  }

  Widget _row(String title, String desc, Widget control) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Tokens.body(size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: Tokens.body(
                    size: 11,
                    color: Tokens.muted,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }

  Widget _notice({required String text}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Tokens.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Tokens.body(size: 11, color: Tokens.muted, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Tokens.chipActiveBg : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          constraints: const BoxConstraints(minHeight: 44, minWidth: 120),
          decoration: active
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x14DDE6F4)),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? Colors.white : Tokens.muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(
                    size: 12,
                    color: active ? Colors.white : Tokens.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Press the button you want" — listens to the controller and returns the
/// first button pressed, or null on Cancel.
class _PressAButtonDialog extends StatefulWidget {
  const _PressAButtonDialog({required this.label});
  final String label;

  @override
  State<_PressAButtonDialog> createState() => _PressAButtonDialogState();
}

class _PressAButtonDialogState extends State<_PressAButtonDialog> {
  void Function()? _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = GamepadService.shared.onButton((e) {
      if (!e.pressed || !padButtons.contains(e.code)) return;
      _cancel?.call();
      _cancel = null;
      if (mounted) Navigator.of(context).pop(e.code);
    });
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Tokens.panel,
    title: Text('Set ${widget.label}', style: Tokens.display(size: 18)),
    content: Text(
      'Press the controller button you want to use.',
      style: Tokens.body(size: 13, color: Tokens.muted),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}
