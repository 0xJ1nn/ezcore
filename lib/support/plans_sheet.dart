import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'diamond_tokens.dart';
import 'entitlement.dart';
import 'open_url.dart';
import 'purchase_store.dart';
import 'support_ui.dart';

/// The Diamond plans sheet (design frame 2). Prices and period strings come
/// from the store via [StoreProduct]; only the fake store supplies the design's
/// dollar values in tests and captures.
class PlansSheet extends StatefulWidget {
  const PlansSheet({
    super.key,
    required this.products,
    required this.trialEligible,
    this.storeName = 'App Store',
    this.onBuy,
    this.onRestore,
  });

  final List<StoreProduct> products;
  final bool trialEligible;
  final String storeName;
  final ValueChanged<String>? onBuy;
  final VoidCallback? onRestore;

  @override
  State<PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends State<PlansSheet> {
  int _selected = 2; // yearly is selected by default in the design
  int _focus = 2;

  List<StoreProduct> get _plans =>
      widget.products.where((p) => p.isPlan).toList();

  StoreProduct? get _current {
    final plans = _plans;
    if (plans.isEmpty) return null;
    if (_selected >= plans.length) return plans.last;
    return plans[_selected];
  }

  void _move(int delta) {
    final count = _plans.length + 1; // plans + CTA
    setState(() => _focus = (_focus + delta + count) % count);
  }

  void _activate(BuildContext context) {
    if (_focus < _plans.length) {
      setState(() => _selected = _focus);
      return;
    }
    final plan = _current;
    if (plan != null) {
      Navigator.of(context).maybePop();
      widget.onBuy?.call(plan.id);
    }
  }

  String get _ctaLabel => widget.trialEligible
      ? 'Start 7-day free trial'
      : 'Subscribe to Diamond';

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    final plan = _current;
    final plans = _plans;
    return SupportSheetFrame(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              _activate(context),
          const SingleActivator(LogicalKeyboardKey.select): () =>
              _activate(context),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              _activate(context),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset(
                  DiamondTokens.gem44,
                  width: phone ? 40 : 44,
                  height: phone ? 40 : 44,
                ),
                SizedBox(width: phone ? 10 : 14),
                Text(
                  'ezCORE Diamond',
                  style: Tokens.display(
                    size: phone ? 26 : 30,
                    weight: FontWeight.w600,
                    ls: -0.02 * 30,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            SizedBox(height: phone ? 8 : 10),
            Text(
              'Get new features and systems 60 days before they reach the free '
              'app, plus Diamond icons, an accent colour and your name in the '
              'credits.',
              style: Tokens.body(
                size: 15,
                color: Tokens.muted,
                height: 1.5,
              ),
            ),
            SizedBox(height: phone ? 18 : 22),
            for (var i = 0; i < plans.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanRow(
                  product: plans[i],
                  selected: i == _selected,
                  focused: i == _focus,
                  showTrial: widget.trialEligible &&
                      plans[i].id == diamondYearlyId,
                  onTap: () => setState(() {
                    _selected = i;
                    _focus = i;
                  }),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SupportButton(
                label: _ctaLabel,
                style: 'dia',
                width: double.infinity,
                onTap: () {
                  final p = _current;
                  if (p != null) {
                    Navigator.of(context).maybePop();
                    widget.onBuy?.call(p.id);
                  }
                },
              ),
            ),
            SizedBox(height: phone ? 14 : 16),
            Text(
              plan == null
                  ? 'Plans are not available right now.'
                  : widget.trialEligible
                  ? 'Free for 7 days, then ${plan.price} ${plan.period}. '
                      'Renews automatically until you cancel, at least 24 '
                      'hours before the renewal date, in your '
                      '${widget.storeName} account settings. ezCORE works '
                      'fully without Diamond.'
                  : '${plan.price} ${plan.period}. Renews automatically until '
                      'you cancel, at least 24 hours before the renewal date, '
                      'in your ${widget.storeName} account settings. ezCORE '
                      'works fully without Diamond.',
              style: Tokens.body(
                size: 12,
                color: DiamondTokens.faint,
                height: 1.55,
              ),
            ),
            SizedBox(height: phone ? 12 : 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: phone ? 12 : 18,
              runSpacing: 8,
              children: [
                _Link(
                  label: 'Restore purchases',
                  onTap: () {
                    Navigator.of(context).maybePop();
                    widget.onRestore?.call();
                  },
                ),
                _Link(
                  label: 'Terms of Use',
                  onTap: () => openSupportUrl(DiamondTokens.termsUrl),
                ),
                _Link(
                  label: 'Privacy Policy',
                  onTap: () => openSupportUrl(DiamondTokens.privacyUrl),
                ),
              ],
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

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.product,
    required this.selected,
    required this.focused,
    required this.showTrial,
    required this.onTap,
  });

  final StoreProduct product;
  final bool selected;
  final bool focused;
  final bool showTrial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = focused
        ? Border.all(color: const Color(0xE64DA3FF), width: 1.5)
        : selected
        ? Border.all(color: const Color(0xB3A8CEFF))
        : Border.all(color: Tokens.line);
    return Semantics(
      button: true,
      selected: selected,
      label: product.title,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Tokens.fastDur,
          curve: Tokens.ease,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? DiamondTokens.card : const Color(0x05FFFFFF),
            border: border,
            boxShadow: selected ? DiamondTokens.glow : null,
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? DiamondTokens.blue2 : const Color(0x4DFFFFFF),
                    width: selected ? 7 : 2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product.title,
                            style: Tokens.body(
                              size: 17,
                              weight: FontWeight.w700,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                        ),
                        if (showTrial) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: DiamondTokens.fg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '7 DAYS FREE',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.14 * 10,
                                color: Color(0xFF0A1A2E),
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.description,
                      style: Tokens.body(
                        size: 13,
                        color: Tokens.muted,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.price,
                    style: Tokens.display(
                      size: 22,
                      weight: FontWeight.w700,
                      ls: 0,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.period,
                    style: Tokens.body(
                      size: 12,
                      color: Tokens.muted,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: Tokens.body(
          size: 13,
          weight: FontWeight.w600,
          color: Tokens.muted,
          height: 1,
        ).copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}

/// Opens the plans sheet over the app with the design's scrim and rise.
Future<void> showPlansSheet(
  BuildContext context, {
  required Entitlement entitlement,
}) {
  return showSupportSheet(
    context,
    builder: (_) => ListenableBuilder(
      listenable: entitlement,
      builder: (context, _) => PlansSheet(
        products: entitlement.products,
        trialEligible: entitlement.trialEligible,
        storeName: entitlement.store.isAvailable ? 'App Store' : 'store',
        onBuy: (id) => entitlement.buy(id),
        onRestore: () => entitlement.restore(),
      ),
    ),
  );
}
