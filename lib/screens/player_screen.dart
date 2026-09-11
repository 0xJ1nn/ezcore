import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'cheats_screen.dart';

/// Player chrome over the native canvas. The canvas itself is a Texture
/// fed by the ezCore runtime once a core is loaded; until then this screen
/// shows the session HUD around a placeholder.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.gameId, required this.state});
  final String gameId;
  final AppState state;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool paused = false;
  bool fastForward = false;
  bool padVisible = true;

  @override
  Widget build(BuildContext context) {
    final game = widget.state.games.firstWhere((g) => g.id == widget.gameId);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${game.system} · ${game.coreId}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(Tokens.pad),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
                border: Border.all(color: Tokens.inkLine),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    paused ? Icons.pause_circle : Icons.videogame_asset,
                    size: 56,
                    color: Tokens.muted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paused ? 'Paused' : game.title,
                    style: const TextStyle(color: Tokens.muted),
                  ),
                  const Text(
                    'Native canvas binds here (runtime → Texture)',
                    style: TextStyle(color: Tokens.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (padVisible)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Touch pad overlay binds here',
                style: TextStyle(color: Tokens.muted, fontSize: 11),
              ),
            ),
          _pad(),
        ],
      ),
    );
  }

  Widget _pad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        color: Tokens.inkRaised,
        border: Border(top: BorderSide(color: Tokens.inkLine)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              tooltip: paused ? 'Resume' : 'Pause',
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              onPressed: () => setState(() => paused = !paused),
            ),
            IconButton(
              tooltip: 'Quick-save',
              icon: const Icon(Icons.save_outlined),
              onPressed: () => _toast('Saved to slot 0'),
            ),
            IconButton(
              tooltip: 'Fast-forward',
              icon: Icon(
                Icons.fast_forward_outlined,
                color: fastForward ? Tokens.coin : null,
              ),
              onPressed: () {
                setState(() => fastForward = !fastForward);
                _toast(fastForward ? 'Fast-forward on' : 'Fast-forward off');
              },
            ),
            IconButton(
              tooltip: 'Screenshot',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: () => _toast('Screenshot saved'),
            ),
            IconButton(
              tooltip: 'Pad overlay',
              icon: const Icon(Icons.gamepad_outlined),
              onPressed: () => setState(() => padVisible = !padVisible),
            ),
            IconButton(
              tooltip: 'Cheats',
              icon: const Icon(Icons.bolt_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CheatsScreen(gameId: widget.gameId, state: widget.state),
                ),
              ),
            ),
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz),
              onPressed: _more,
            ),
          ],
        ),
      ),
    );
  }

  void _more() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Save state slot…'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Load state…'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Core options…'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset'),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close game'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
