import 'package:flutter/material.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/diamond_badge.dart';
import 'diamond_tokens.dart';
import 'early_access.dart';
import 'entitlement.dart';
import 'open_url.dart';
import 'support_ui.dart';
import 'thanks_overlay.dart';

const _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Settings › Diamond. The pane changes with membership and with whether this
/// build has a store. Every state is a plain card, matching the design.
class DiamondSection extends StatefulWidget {
  const DiamondSection({
    super.key,
    required this.entitlement,
    this.onSeePlans,
    this.onRestore,
    this.onManage,
    this.onTips,
  });

  final Entitlement entitlement;
  final VoidCallback? onSeePlans;
  final VoidCallback? onRestore;
  final VoidCallback? onManage;
  final VoidCallback? onTips;

  @override
  State<DiamondSection> createState() => _DiamondSectionState();
}

class _DiamondSectionState extends State<DiamondSection> {
  bool _accent = true;
  bool _credits = false;

  @override
  void initState() {
    super.initState();
    final values = widget.entitlement.storage.values;
    _accent = values['diamond.accent'] != false;
    _credits = values['diamond.credits'] == true;
  }

  void _toggleAccent(bool value) {
    setState(() => _accent = value);
    widget.entitlement.storage.write('diamond.accent', value);
  }

  void _toggleCredits(bool value) {
    setState(() => _credits = value);
    widget.entitlement.storage.write('diamond.credits', value);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.entitlement,
      builder: (context, _) {
        if (!widget.entitlement.storeAvailable) {
          return const _SponsorsCard();
        }
        return widget.entitlement.isDiamond
            ? _member(context)
            : _notMember(context);
      },
    );
  }

  Widget _notMember(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          hero: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(DiamondTokens.gem64, width: 64, height: 64),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ezCORE Diamond',
                      style: Tokens.display(
                        size: 26,
                        weight: FontWeight.w600,
                        ls: -0.02 * 26,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'New features and systems reach Diamond members first. '
                      'Every one of them comes to the free app 60 days later. '
                      'ezCORE itself stays free, with every core and every '
                      'feature.',
                      style: Tokens.body(
                        size: 15,
                        color: Tokens.muted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      children: [
                        SupportButton(
                          label: 'See plans',
                          icon: Symbols.diamond,
                          width: 160,
                          onTap: widget.onSeePlans,
                        ),
                        SupportButton(
                          label: 'Restore purchases',
                          style: 'sec',
                          width: 200,
                          onTap: widget.onRestore,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'IN DIAMOND NOW',
            style: Tokens.body(
              size: 12,
              weight: FontWeight.w600,
              ls: 0.24 * 12,
              color: Tokens.muted,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Card(
          child: earlyAccessFeatures.isEmpty
              ? Text(
                  'Nothing in early access right now.',
                  style: Tokens.body(
                    size: 15,
                    color: Tokens.muted,
                    height: 1.45,
                  ),
                )
              : Column(
                  children: [
                    for (final feature in earlyAccessFeatures)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              feature.icon,
                              size: 22,
                              color: DiamondTokens.fg,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                feature.title,
                                style: Tokens.body(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ),
                            Text(
                              'Free for everyone on ${_date(feature.freeFrom)}',
                              style: Tokens.body(
                                size: 13,
                                color: Tokens.muted,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        _TipCard(
          focused: true,
          description:
              'A coffee, a pizza, a console. It unlocks nothing; it just says '
              'thanks.',
          onTap: widget.onTips,
        ),
      ],
    );
  }

  Widget _member(BuildContext context) {
    final entitlement = widget.entitlement;
    final plans = entitlement.products
        .where((p) => p.id == entitlement.activePlan)
        .toList();
    final plan = plans.isEmpty ? null : plans.first;
    final planName = plan?.title ?? 'Diamond';
    final price = plan?.price ?? '';
    final renew = entitlement.renewDate;
    final detail = StringBuffer(planName);
    if (!detail.toString().endsWith('plan')) detail.write(' plan');
    if (renew != null) detail.write(' · renews on ${_date(renew)}');
    if (price.isNotEmpty) detail.write(' for $price');
    detail.write('. Thank you for keeping ezCORE free for everyone.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          hero: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(DiamondTokens.gem64, width: 64, height: 64),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          'ezCORE Diamond',
                          style: Tokens.display(
                            size: 26,
                            weight: FontWeight.w600,
                            ls: -0.02 * 26,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const DiamondBadge(
                          label: 'Diamond member',
                          large: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail.toString(),
                      style: Tokens.body(
                        size: 15,
                        color: Tokens.muted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SupportButton(
                      label: 'Manage subscription',
                      style: 'sec',
                      width: 210,
                      onTap: widget.onManage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ToggleCard(
          label: 'Diamond accent',
          description: 'Ice-blue highlights across the app.',
          value: _accent,
          onChanged: _toggleAccent,
        ),
        const SizedBox(height: 8),
        _ToggleCard(
          label: 'Name in the credits',
          description: 'Shown in About › Thanks. Off unless you turn it on.',
          value: _credits,
          onChanged: _toggleCredits,
        ),
        const SizedBox(height: 8),
        _TipCard(
          description: '${describeTally(entitlement.tipTally)} Thank you.',
          onTap: widget.onTips,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.hero = false, this.focused = false});

  final Widget child;
  final bool hero;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: hero
          ? const EdgeInsets.fromLTRB(26, 26, 26, 24)
          : const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: hero ? null : DiamondTokens.card,
        gradient: hero
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x244DA3FF), Color(0xC70F1825)],
                stops: [0.0, 0.55],
              )
            : null,
        border: Border.all(
          color: focused
              ? const Color(0xE64DA3FF)
              : hero
              ? const Color(0x47A8CEFF)
              : Tokens.line,
          width: focused ? 1.5 : 1,
        ),
        boxShadow: focused
            ? const [
                BoxShadow(
                  color: Color(0x8C007BFF),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.description, this.focused = false, this.onTap});

  final String description;
  final bool focused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _Card(
      focused: focused,
      child: Row(
        children: [
          Icon(Symbols.coffee, size: 26, color: DiamondTokens.fg),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send the developer something',
                  style: Tokens.body(
                    size: 18,
                    weight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Tokens.body(
                    size: 14,
                    color: Tokens.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Symbols.chevronRight, size: 26, color: Tokens.muted),
        ],
      ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Tokens.body(
                    size: 18,
                    weight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Tokens.body(
                    size: 14,
                    color: Tokens.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: Tokens.fastDur,
              curve: Tokens.ease,
              width: 56,
              height: 32,
              padding: const EdgeInsets.all(4),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? Tokens.accent : Tokens.toggleOff,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? Colors.white : Tokens.toggleKnobOff,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SponsorsCard extends StatelessWidget {
  const _SponsorsCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openSupportUrl(DiamondTokens.sponsorsUrl),
      child: _Card(
      child: Row(
        children: [
          const Icon(Symbols.favorite, size: 26, color: DiamondTokens.fg),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support ezCORE on GitHub Sponsors',
                  style: Tokens.body(
                    size: 18,
                    weight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This build has no in-app store. Contributions here are '
                  'entirely optional.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    color: Tokens.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Symbols.chevronRight, size: 26, color: Tokens.muted),
        ],
      ),
      ),
    );
  }
}
