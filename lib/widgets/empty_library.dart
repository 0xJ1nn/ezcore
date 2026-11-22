// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter/material.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'library_looks/library_cover.dart';

/// The empty library (handoff §8.1): five dashed ghost covers standing on a
/// lit ledge, one sentence explaining why the shelf is bare, and the two ways
/// forward. No store, no download, no implied game content.
///
/// The phone frame shows the centre ghost and its two neighbours (the outer
/// pair sit past the bezel); wider surfaces show all five at the measured
/// 150×200 size. One widget, one set of copy, on every family.
class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({
    super.key,
    required this.onAddGames,
    this.onOpenSystems,
    this.phone = false,
  });

  final VoidCallback onAddGames;

  /// When null the secondary action opens the folder picker instead. The
  /// shell supplies a Systems callback, which is what the device render shows.
  final VoidCallback? onOpenSystems;

  final bool phone;

  static const _copy =
      'ezCORE ships no games. Point it at a folder of games you own and '
      'they’ll appear here, sorted by system.';

  @override
  Widget build(BuildContext context) {
    final secondaryLabel = onOpenSystems == null
        ? 'Choose a folder'
        : 'Open Systems';
    return LayoutBuilder(
      builder: (context, c) {
        final contentHeight = c.maxHeight;
        // A narrow desktop window cannot fit the two measured buttons side by
        // side; stack them as the phone frame does rather than overflow.
        final compact = phone || c.maxWidth < 420;
        // 168 on the 844-tall phone frame puts the ghost shelf where the
        // design's lit ledge sits, below the brand lockup and clear of it.
        final topSpace = phone
            ? (contentHeight * 0.225).clamp(120.0, 172.0)
            : 34.0;
        return SingleChildScrollView(
          child: SizedBox(
            width: c.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topSpace),
                Center(child: _GhostShelf(phone: phone)),
                SizedBox(height: phone ? 82 : 30),
                Text(
                  'Your shelf is empty',
                  textAlign: TextAlign.center,
                  style: Tokens.display(
                    size: compact ? 26 : 32,
                    weight: FontWeight.w600,
                    ls: -0.02 * (compact ? 26 : 32),
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 40 : 80),
                  child: Text(
                    _copy,
                    textAlign: TextAlign.center,
                    style: Tokens.body(
                      size: compact ? 15 : 17,
                      color: Tokens.muted,
                      height: 1.5,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 48 : 40),
                if (compact)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ActionButton(
                          label: 'Add games',
                          icon: Symbols.createNewFolder,
                          primary: true,
                          onPressed: onAddGames,
                        ),
                        const SizedBox(height: 12),
                        _ActionButton(
                          label: secondaryLabel,
                          icon: Symbols.sportsEsports,
                          primary: false,
                          onPressed: onOpenSystems ?? onAddGames,
                          height: 50,
                          fontSize: 15,
                        ),
                      ],
                    ),
                  )
                else
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionButton(
                          label: 'Add games',
                          icon: Symbols.createNewFolder,
                          primary: true,
                          onPressed: onAddGames,
                        ),
                        const SizedBox(width: 12),
                        _ActionButton(
                          label: secondaryLabel,
                          icon: Symbols.sportsEsports,
                          primary: false,
                          onPressed: onOpenSystems ?? onAddGames,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Five dashed covers and the blue ledge they stand on. Positions are read
/// from the design render: the centre cover is 110×148 on a phone and the two
/// neighbours are 64×93, dropping 55 px and ending on the same baseline.
class _GhostShelf extends StatelessWidget {
  const _GhostShelf({required this.phone});

  final bool phone;

  @override
  Widget build(BuildContext context) {
    final w = phone ? 110.0 : 150.0;
    final h = phone ? 148.0 : 200.0;
    final sideW = phone ? 64.0 : 118.0;
    final sideH = phone ? 93.0 : 160.0;
    final gap = phone ? 15.0 : 28.0;
    final drop = phone ? 55.0 : 40.0;
    final height = h + (phone ? 50.0 : 48.0);
    final dash = BorderRadius.circular(6);

    Widget box(double width, double height) => Container(
      key: const Key('ghost-cover'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: dash,
        border: Border.all(
          color: Tokens.text.withValues(alpha: 0.16),
          width: 1.5,
        ),
        color: Tokens.text.withValues(alpha: 0.02),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        // On a phone the outer pair is pushed past the sides of the screen
        // and clipped by the viewport, leaving exactly three visible ghosts.
        final width = c.maxWidth.isFinite ? c.maxWidth : 390.0;
        final centre = width / 2;
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned(
                top: drop,
                left: centre - w / 2 - gap - sideW,
                child: box(sideW, sideH),
              ),
              Positioned(
                top: drop,
                left: centre + w / 2 + gap,
                child: box(sideW, sideH),
              ),
              Positioned(
                top: drop,
                left: phone ? -400 : centre - w / 2 - 2 * gap - 2 * sideW,
                child: box(sideW, sideH),
              ),
              Positioned(
                top: drop,
                left: phone ? width + 300 : centre + w / 2 + 2 * gap + sideW,
                child: box(sideW, sideH),
              ),
              Positioned(top: 0, left: centre - w / 2, child: box(w, h)),
              Positioned(
                left: phone ? 44 : 0,
                right: phone ? 44 : 0,
                bottom: 0,
                height: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Tokens.planetRim.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Tokens.planetRim.withValues(alpha: 0.6),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
    this.height = Tokens.ctaHeight,
    this.fontSize = 17,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // LookTile is the app's one focus owner: the empty state's actions stay in
    // the same arrow-key/d-pad traversal as every cover and rail stop, so a
    // newcomer can reach "Add games" without a pointer on desktop or TV.
    return LookTile(
      onTap: onPressed,
      radius: Tokens.radiusPrimary,
      semanticLabel: label,
      semanticHint: primary ? 'Add the games you own' : null,
      lift: 1.02,
      child: Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(
          Tokens.ctaPadLeft,
          0,
          Tokens.ctaPadRight,
          0,
        ),
        alignment: Alignment.center,
        decoration: primary ? Tokens.primaryButton() : Tokens.secondaryButton(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: Tokens.ctaIconSize,
              color: primary ? Colors.white : Tokens.text,
            ),
            const SizedBox(width: Tokens.dockGap),
            // LookTile owns the spoken label; exclude the visible Text so the
            // merged node announces "Add games" once, not twice.
            ExcludeSemantics(
              child: Text(
                label,
                style: Tokens.body(
                  size: fontSize,
                  weight: FontWeight.w700,
                  color: primary ? Colors.white : Tokens.text,
                  height: null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
