import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Case de consentement obligatoire du formulaire de candidature.
///
/// Reprend le style « pastille dégradée + coche » de la maquette
/// `BecomeArtist.dc.html`, plutôt qu'une `Checkbox` Material standard, pour
/// rester cohérent avec l'identité visuelle des CTA du design system.
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  static const String _label =
      'Je certifie être l\'artiste ou son représentant et j\'accepte les '
      'conditions de vérification.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: _label,
      checked: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          // Cible tactile ≥ 48 dp malgré la petite pastille visuelle.
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: value ? vibeo.gradient : null,
                  color: value ? null : scheme.surfaceContainerHigh,
                  border: value
                      ? null
                      : Border.all(color: scheme.outlineVariant, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
