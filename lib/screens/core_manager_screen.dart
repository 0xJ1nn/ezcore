import 'package:flutter/material.dart';

import '../cores/core_registry.dart';
import '../models/core_manifest.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class CoreManagerScreen extends StatelessWidget {
  const CoreManagerScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.registry,
      builder: (context, _) {
        final catalog = state.registry.catalog;
        final installed =
            catalog.where((m) => state.registry.isInstalled(m.id)).toList();
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: 'Installed (${installed.length})'),
                  Tab(text: 'Catalog (${catalog.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _list(context, installed, installedOnly: true),
                    _list(context, catalog, installedOnly: false),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(
    BuildContext context,
    List<CoreManifest> cores, {
    required bool installedOnly,
  }) {
    final shown = installedOnly
        ? cores
        : cores.where((m) => !state.registry.isInstalled(m.id)).toList();
    if (shown.isEmpty) {
      return const Center(child: Text('Nothing here yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(Tokens.pad),
      itemCount: shown.length,
      itemBuilder: (context, i) => _row(context, shown[i]),
    );
  }

  Widget _row(BuildContext context, CoreManifest m) {
    final status = state.registry.statusOf(m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.name} ${m.version}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${m.systems.join(' · ')}\n${m.license} · ${m.homepage}',
              style: const TextStyle(fontSize: 12, color: Tokens.muted),
            ),
            if (m.blocked) ...[
              const SizedBox(height: 6),
              Text(
                'Legal hold: ${m.blockedReason}',
                style: const TextStyle(fontSize: 12, color: Tokens.coin),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (status == CoreStatus.notInstalled)
                  FilledButton(
                    onPressed: () => _install(context, m),
                    child: const Text('Install'),
                  ),
                if (status == CoreStatus.updateAvailable)
                  FilledButton(
                    onPressed: () => _install(context, m),
                    child: const Text('Update'),
                  ),
                if (status == CoreStatus.installed ||
                    status == CoreStatus.updateAvailable) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => state.registry.remove(m.id),
                    child: const Text('Remove'),
                  ),
                ],
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('${m.name} license'),
                      content: Text(
                        '${m.license}\n\nCheats: ${m.cheatsSupported ? m.cheatFamilies.join(', ') : 'not supported'}\nBIOS: ${m.biosRequired ? 'required — ${m.biosFiles.join(', ')}' : 'not required'}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('License'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(CoreStatus status) {
    final label = switch (status) {
      CoreStatus.installed => 'installed',
      CoreStatus.notInstalled => 'not installed',
      CoreStatus.updateAvailable => 'update',
      CoreStatus.blocked => 'legal hold',
    };
    final color = switch (status) {
      CoreStatus.installed => Tokens.ok,
      CoreStatus.updateAvailable => Tokens.coin,
      CoreStatus.blocked => Tokens.danger,
      CoreStatus.notInstalled => Tokens.muted,
    };
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }

  void _install(BuildContext context, CoreManifest m) {
    try {
      // v0: artifacts land via scripts/build_core.sh; the sha is verified
      // against the manifest pin before dlopen in the native loader.
      final sha = m.artifacts.values.firstOrNull ?? 'dev-unverified';
      state.registry.install(m, expectedSha256: sha);
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}
