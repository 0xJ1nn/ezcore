import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How a collection (the library, the cores) is shown. One choice per
/// collection, remembered in settings.
enum CollectionView {
  flow('3d', '3D', Icons.view_carousel_outlined),
  grid('grid', 'Grid', Icons.grid_view_rounded),
  list('list', 'List', Icons.view_agenda_outlined);

  const CollectionView(this.value, this.label, this.icon);

  /// The value stored in settings.
  final String value;
  final String label;
  final IconData icon;

  static CollectionView fromSetting(
    Object? raw, {
    CollectionView fallback = grid,
  }) {
    for (final v in values) {
      if (v.value == raw) return v;
    }
    return fallback;
  }
}

/// Settings keys for each collection's view.
const libraryViewKey = 'libraryView';
const coresViewKey = 'coresView';

/// The 3D / Grid / List switch: three icons in one pill, the current one lit.
class CollectionViewSwitch extends StatelessWidget {
  const CollectionViewSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CollectionView value;
  final ValueChanged<CollectionView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x0ADDE6F4),
        borderRadius: BorderRadius.circular(Tokens.radiusRound),
        border: Border.all(color: const Color(0x21DDE6F4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in CollectionView.values)
            _SwitchButton(
              view: v,
              active: v == value,
              onTap: () => onChanged(v),
            ),
        ],
      ),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({
    required this.view,
    required this.active,
    required this.onTap,
  });

  final CollectionView view;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '${view.label} view',
      child: Tooltip(
        message: view.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          focusColor: const Color(0x33007BFF),
          child: AnimatedContainer(
            duration: Tokens.fastDur,
            width: 40,
            height: 36,
            decoration: BoxDecoration(
              color: active ? const Color(0x26007BFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(Tokens.radiusSm),
              border: Border.all(
                color: active ? const Color(0x80007BFF) : Colors.transparent,
              ),
            ),
            child: Icon(
              view.icon,
              size: 19,
              color: active ? Colors.white : Tokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}
