import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_providers.dart';

/// Barre de recherche en pilule (voir `Maquettes/Search.dc.html`).
///
/// Le texte tapé alimente immédiatement le champ ; [SearchQueryController]
/// applique son propre délai d'attente avant de déclencher la requête. Un
/// `ref.listen` resynchronise le champ si la requête est effacée ailleurs
/// (bouton « Effacer la recherche » de l'état « aucun résultat »).
class SearchBarField extends ConsumerStatefulWidget {
  const SearchBarField({super.key});

  @override
  ConsumerState<SearchBarField> createState() => _SearchBarFieldState();
}

class _SearchBarFieldState extends ConsumerState<SearchBarField> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchQueryProvider).text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // Actualise la visibilité du bouton d'effacement.
    ref.read(searchQueryProvider.notifier).setText(value);
  }

  void _clear() {
    _controller.clear();
    setState(() {});
    ref.read(searchQueryProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Resynchronise le champ si le texte change hors de ce widget (ex. le
    // bouton « Effacer la recherche » de l'état vide).
    ref.listen<SearchQuery>(searchQueryProvider, (previous, next) {
      if (next.text != _controller.text) {
        _controller.value = _controller.value.copyWith(
          text: next.text,
          selection: TextSelection.collapsed(offset: next.text.length),
        );
      }
    });

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) =>
                  ref.read(searchQueryProvider.notifier).submit(value),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'Rechercher un clip, un artiste…',
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Effacer la recherche',
              onPressed: _clear,
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
