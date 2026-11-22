// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'diamond_tokens.dart';
import 'entitlement.dart';
import 'purchase_store.dart';
import 'support_ui.dart';

/// Icon and label for each tip, ported from the design's tip sheet.
const tipItems = <(String, String, IconData)>[
  ('tip.coffee', 'Coffee', Symbols.coffee),
  ('tip.pizza', 'Pizza', Symbols.localPizza),
  ('tip.gamepad', 'Gamepad', Symbols.sportsEsports),
  ('tip.console', 'Console', Symbols.videogameAsset),
  ('tip.arcade', 'Arcade cabinet', Symbols.joystick),
  ('tip.devkit', 'Dev kit', Symbols.developerBoard),
];

class TipsSheet extends StatefulWidget {
  const TipsSheet({
    super.key,
    required this.products,
    this.onBuy,
  });

  final List<StoreProduct> products;
  final ValueChanged<String>? onBuy;

  @override
  State<TipsSheet> createState() => _TipsSheetState();
}

class _TipsSheetState extends State<TipsSheet> {
  int _focus = 0;

  String _price(String id) {
    for (final p in widget.products) {
      if (p.id == id) return p.price;
    }
    return '';
  }

  void _move(int delta) {
    setState(() => _focus = (_focus + delta + tipItems.length) % tipItems.length);
  }

  void _buy(BuildContext context, String id) {
    Navigator.of(context).maybePop();
    widget.onBuy?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    final columns = phone ? 2 : 3;
    return SupportSheetFrame(
      padding: const EdgeInsets.fromLTRB(36, 14, 36, 24),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _move(columns),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _move(-columns),
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              _buy(context, tipItems[_focus].$1),
          const SingleActivator(LogicalKeyboardKey.select): () =>
              _buy(context, tipItems[_focus].$1),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              _buy(context, tipItems[_focus].$1),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Send the developer something',
              style: Tokens.display(
                size: phone ? 26 : 30,
                weight: FontWeight.w600,
                ls: -0.02 * 30,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            SizedBox(height: phone ? 8 : 10),
            Text(
              'Pick anything, as often as you like. A tip unlocks nothing; it '
              'just says thanks.',
              style: Tokens.body(
                size: 15,
                color: Tokens.muted,
                height: 1.5,
              ),
            ),
            SizedBox(height: phone ? 18 : 22),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: phone ? 1.08 : 1.45,
              ),
              itemCount: tipItems.length,
              itemBuilder: (context, i) {
                final (id, name, icon) = tipItems[i];
                return _TipTile(
                  icon: icon,
                  name: name,
                  price: _price(id),
                  focused: i == _focus,
                  onTap: () => _buy(context, id),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'One-time purchase each time. Nothing renews.',
              textAlign: TextAlign.center,
              style: Tokens.body(
                size: 12,
                color: DiamondTokens.faint,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: SupportHintBar(
                hints: const [('Enter', 'Choose'), ('Esc', 'Close')],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipTile extends StatelessWidget {
  const _TipTile({
    required this.icon,
    required this.name,
    required this.price,
    required this.focused,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String price;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Telemetry.tipFocus,
          curve: Tokens.ease,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0x06FFFFFF),
            border: focused
                ? Border.all(color: const Color(0xE64DA3FF), width: 1.5)
                : Border.all(color: Tokens.line),
            boxShadow: focused
                ? const [
                    BoxShadow(
                      color: Color(0x554DA3FF),
                      blurRadius: 22,
                      spreadRadius: -8,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: focused ? 1.06 : 1.0,
                duration: Telemetry.tipFocus,
                curve: Tokens.ease,
                child: AnimatedContainer(
                duration: Telemetry.tipFocus,
                curve: Tokens.ease,
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const RadialGradient(
                    center: Alignment(0, -0.3),
                    colors: [Color(0x474DA3FF), Color(0x0F4DA3FF)],
                  ),
                  border: Border.all(color: const Color(0x38A8CEFF)),
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: DiamondTokens.fg,
                ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.body(
                  size: 16,
                  weight: FontWeight.w700,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: Tokens.body(
                  size: 14,
                  weight: FontWeight.w600,
                  color: DiamondTokens.blue2,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showTipsSheet(
  BuildContext context, {
  required Entitlement entitlement,
}) {
  return showSupportSheet(
    context,
    builder: (_) => TipsSheet(
      products: entitlement.products,
      onBuy: (id) => entitlement.buy(id),
    ),
  );
}
