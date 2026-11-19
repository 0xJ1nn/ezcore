import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The player stage behind the game. The device boards put the controls on
/// ink in portrait and on a quiet radial wash in landscape; edit mode keeps
/// the ink so the editing handles stay legible. Everything else stays black.
class StageBackdrop extends StatelessWidget {
  const StageBackdrop({
    super.key,
    required this.phone,
    this.landscape = false,
    this.editing = false,
  });

  final bool phone;
  final bool landscape;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    if (!phone) return const ColoredBox(color: Colors.black);
    if (!landscape || editing) {
      return const ColoredBox(color: Tokens.playerInk);
    }
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [Tokens.playerGlow, Tokens.playerEdge],
        ),
      ),
    );
  }
}
