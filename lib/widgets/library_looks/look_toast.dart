// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/symbols.dart';
import '../../theme/tokens.dart';

/// The small "Library look: Shelf" pill that confirms a look change (§8.1).
///
/// It sits over the bottom of the game dock rather than in the toast stack,
/// so it uses the design's 38 px pill instead of the app's 52 px one.
void showLibraryLookToast(BuildContext context, String label) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _LookToast(
      message: 'Library look: $label',
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _LookToast extends StatefulWidget {
  const _LookToast({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_LookToast> createState() => _LookToastState();
}

class _LookToastState extends State<_LookToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Tokens.baseDur,
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2600), _hide);
  }

  Future<void> _hide() async {
    _timer?.cancel();
    if (!_controller.isCompleted) return;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 84,
      child: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Tokens.ease),
          child: Container(
            height: 38,
            padding: const EdgeInsets.only(left: 14, right: 18),
            decoration: BoxDecoration(
              color: const Color(0xF20E1A24),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: const Color(0xFF24384A)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80000000),
                  offset: Offset(0, 8),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Tokens.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Symbols.info,
                    size: 11,
                    color: Colors.white,
                    fill: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.message,
                  style: Tokens.body(
                    size: 13.5,
                    weight: FontWeight.w500,
                    color: const Color(0xFFE4EEF6),
                    height: null,
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
