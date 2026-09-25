import 'package:flutter/material.dart';

import '../emu/pcm_output.dart';
import '../services/gamepad.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
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
  final _gamepads = GamepadService();
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
    _gamepads.dispose();
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!compact) ...[
                          Text(
                            'SIMPLE. POWERFUL. EVERYWHERE.',
                            style: Tokens.eyebrow,
                          ),
                          const SizedBox(height: 7),
                        ],
                        Text(
                          'Fine-tune your experience',
                          style: Tokens.display(
                            size: short ? 22 : (portrait ? 25 : 30),
                            weight: FontWeight.w500,
                            ls: -0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Tokens.line),
                      ),
                      child: Text(
                        portrait ? 'LOCAL' : 'LOCAL PREFERENCES',
                        style: Tokens.body(
                          size: 12,
                          ls: 0.8,
                          color: Tokens.muted,
                        ),
                      ),
                    ),
                ],
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
          'A little more you.',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Midnight surfaces, electric-blue highlights. Make it yours.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'Brand palette',
          'Finalized: black, electric blue, silver, white.',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in const [
                Color(0xFF0A0A0A),
                Color(0xFF007BFF),
                Color(0xFFDDE6F4),
                Colors.white,
              ])
                Container(
                  width: 25,
                  height: 25,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c,
                    border: Border.all(color: const Color(0x50DDE6F4)),
                  ),
                ),
            ],
          ),
        ),
        _row(
          'Ambient motion',
          'Planet limb, drifting stars, and the occasional meteor. '
              'Turn off for a completely still sky.',
          OrbitToggle(
            label: 'Ambient motion',
            value: _pref('motion', true),
            onChanged: (v) => _set('motion', v),
          ),
        ),
        _row(
          'Cover reflections',
          'A subtle echo beneath every world.',
          OrbitToggle(
            label: 'Cover reflections',
            value: _pref('reflection', true),
            onChanged: (v) => _set('reflection', v),
          ),
        ),
        _row(
          'Cover flow feel',
          'Choose the depth and snap used on desktop and phone covers.',
          OrbitSelect<String>(
            value: _pref('coverFlowStyle', 'classic'),
            options: const ['classic', 'gentle', 'flat'],
            labels: const {
              'classic': 'Classic',
              'gentle': 'Gentle',
              'flat': 'Flat',
            },
            onChanged: (v) => _set('coverFlowStyle', v ?? 'classic'),
          ),
        ),
        _row(
          'Default library view',
          'Desktop and phone browsing. Tablets keep their focused hub.',
          OrbitSelect<String>(
            value: _pref('layout', 'flow'),
            options: const ['flow', 'grid'],
            onChanged: (v) => _set('layout', v ?? 'flow'),
          ),
        ),
        _row(
          'Compact system list',
          'A little less space between generations.',
          OrbitToggle(
            label: 'Compact system list',
            value: _pref('dense', false),
            onChanged: (v) => _set('dense', v),
          ),
        ),
        _row(
          'Reset',
          'Back to the approved defaults.',
          OrbitSecondary(
            label: 'Reset appearance',
            onPressed: () async {
              await _set('motion', true);
              await _set('reflection', true);
              await _set('coverFlowStyle', 'classic');
              await _set('layout', 'flow');
              await _set('dense', false);
              if (mounted) {
                orbitToast(context, 'Appearance reset');
              }
            },
          ),
        ),
        _notice(),
      ],
    );
  }

  Widget _emulation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Faithful, by default.',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Global preferences. Per-game core choice in the game hub takes priority.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'Automatic snapshots',
          'Saves an auto snapshot when you leave or background the game.',
          OrbitToggle(
            label: 'Automatic snapshots',
            value: _pref('autosave', true),
            onChanged: (v) => _set('autosave', v),
          ),
        ),
        _row(
          'Fast-forward speed',
          'Frames stepped per tick while fast-forward is on.',
          OrbitSelect<String>(
            value: _pref('ffFrames', '4'),
            options: const ['2', '4', '8'],
            labels: const {'2': '2× speed', '4': '4× speed', '8': '8× speed'},
            onChanged: (v) => _set('ffFrames', v ?? '4'),
          ),
        ),
        _row(
          'Core verification',
          'Every core artifact is sha256-checked against its manifest pin before launch.',
          Text(
            'ALWAYS ON',
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
        _row(
          'State format',
          'Snapshots are opaque core bytes, moved as-is and kept on this device.',
          Text(
            'LOCAL VAULT',
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
        _notice(),
      ],
    );
  }

  Widget _controllers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Play your way.',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Keyboard and touch work in the player today. This is the exact live mapping — no claimed devices.',
          style: Tokens.body(size: 12, color: Tokens.muted, height: 1.8),
        ),
        const SizedBox(height: 16),
        _row(
          'Controller',
          _padName == null
              ? 'No controller detected. Pair one to play without touch.'
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
          'Move (D-pad)',
          'Arrow keys drive the RetroPad directions.',
          Text('↑  ↓  ←  →', style: Tokens.body(size: 12, color: Tokens.muted)),
        ),
        _row(
          'B / A buttons',
          'Z is B, X is A.',
          Text('Z  X', style: Tokens.body(size: 12, color: Tokens.muted)),
        ),
        _row(
          'Select / Start',
          'Right Shift is Select, Enter is Start.',
          Text('RSHIFT  ↵', style: Tokens.body(size: 12, color: Tokens.muted)),
        ),
        _row(
          'Touch overlay',
          'On-screen pad inside the player.',
          OrbitToggle(
            label: 'Touch overlay',
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
        _notice(),
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
          'In the pocket.',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Both take effect when a game starts.',
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
          'Drops emulated PCM before it reaches the speaker.',
          OrbitToggle(
            label: 'Mute all audio',
            value: _pref('muted', false),
            onChanged: (v) => _set('muted', v),
          ),
        ),
        _row(
          'Output',
          'Native device sink. If a platform has no sink yet, the player says so instead of staying silent.',
          Text(
            createPlatformPcm().sinkName.toUpperCase(),
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
        _notice(),
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
          'Your files stay yours.',
          style: Tokens.display(size: 26, weight: FontWeight.w500, ls: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Bring your own dumps. Files never leave this device.',
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
          'Time capsule',
          'Local snapshots live on this device.',
          OrbitSecondary(
            label: 'Open capsule',
            onPressed: () => widget.onGoVault?.call(),
          ),
        ),
        _row(
          'Content policy',
          'No games, BIOS, keys, or cheat DBs ship with this app.',
          Text(
            'BYO DUMPS',
            style: Tokens.body(size: 9, ls: 1.0, color: Tokens.muted),
          ),
        ),
        _notice(),
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
          'One beautiful, unified emulator. Game → Play — no core thinking required.',
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
          'Agent + 48h takedown.',
          Text('See DMCA.md', style: Tokens.body(size: 11)),
        ),
        _row(
          'Version',
          'Working title build.',
          Text('0.1.0+1', style: Tokens.body(size: 11)),
        ),
        _notice(
          text:
              'Open-source frontend. Modular, replaceable cores behind a small stable C ABI.',
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

  Widget _notice({String? text}) {
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
              text ??
                  'Local preferences only. UI choices persist on this device; emulation, cloud sync, and hardware connection are not claimed here.',
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
