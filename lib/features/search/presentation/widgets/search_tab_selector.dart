import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_providers.dart';

/// Sélecteur d'onglet Clips / Artistes (soulignement, voir `Search.dc.html`).
class SearchTabSelector extends ConsumerWidget {
  const SearchTabSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(searchTabProvider);
    final notifier = ref.read(searchTabProvider.notifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          _TabItem(
            label: 'Clips',
            selected: selected == SearchTab.clips,
            onTap: () => notifier.select(SearchTab.clips),
          ),
          const SizedBox(width: 20),
          _TabItem(
            label: 'Artistes',
            selected: selected == SearchTab.artists,
            onTap: () => notifier.select(SearchTab.artists),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
