import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Tokens.pad),
      children: const [
        _Section(
          title: 'Video',
          children: [
            _Row(title: 'Aspect ratio', value: 'Auto'),
            _Row(title: 'Integer scaling', value: 'Off'),
            _Row(title: 'Shader', value: 'None (CRT-lite available)'),
          ],
        ),
        _Section(
          title: 'Audio',
          children: [
            _Row(title: 'Latency', value: '64 ms'),
            _Row(title: 'Resampler', value: 'Sinc'),
          ],
        ),
        _Section(
          title: 'Input',
          children: [
            _Row(title: 'Gamepad', value: 'Auto-detect'),
            _Row(title: 'Touch overlay', value: 'On (mobile)'),
            _Row(title: 'Haptics', value: 'On'),
          ],
        ),
        _Section(
          title: 'Updates',
          children: [
            _Row(title: 'Core updates', value: 'Manual check'),
            _Row(title: 'Download on', value: 'Wi-Fi only'),
          ],
        ),
        _Section(
          title: 'Privacy',
          children: [
            _Row(title: 'Telemetry', value: 'Off'),
          ],
        ),
        _Section(
          title: 'Legal',
          children: [
            _Row(title: 'License', value: 'GPL-3.0-only (shell)'),
            _Row(
              title: 'Content policy',
              value: 'Bring your own dumps. No games, BIOS, keys, or cheat DBs ship with this app.',
            ),
            _Row(title: 'DMCA', value: 'Agent + 48h takedown (see DMCA.md)'),
            _Row(title: 'Version', value: '0.1.0+1'),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Tokens.muted),
            ),
          ),
        ],
      ),
    );
  }
}
