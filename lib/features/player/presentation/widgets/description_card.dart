import 'package:flutter/material.dart';

/// Carte de description repliable (« …plus » / « moins »).
///
/// Texte brut uniquement : le contenu vient d'un utilisateur et ne doit
/// jamais être interprété comme du HTML.
class DescriptionCard extends StatefulWidget {
  const DescriptionCard({required this.text, super.key});

  final String text;

  @override
  State<DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: RichText(
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          text: TextSpan(
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            children: [
              TextSpan(text: widget.text),
              TextSpan(
                text: _expanded ? '  moins' : '  …plus',
                style: TextStyle(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
