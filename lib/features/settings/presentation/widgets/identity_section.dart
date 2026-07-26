import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/legal_identity.dart';
import '../providers/account_providers.dart';
import 'settings_section_card.dart';

/// Section « Identité civile » : prénom, nom, post-nom (optionnel).
///
/// Écrit dans `user_identities`, jamais dans `profiles` (voir
/// `20260726020000_phase35.sql` §1) : ce n'est PAS le nom de scène public.
class IdentitySection extends ConsumerStatefulWidget {
  const IdentitySection({required this.userId, this.identity, super.key});

  final String userId;
  final LegalIdentity? identity;

  @override
  ConsumerState<IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends ConsumerState<IdentitySection> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameCtrl = TextEditingController(
    text: widget.identity?.legalFirstName ?? '',
  );
  late final _lastNameCtrl = TextEditingController(
    text: widget.identity?.legalLastName ?? '',
  );
  late final _middleNameCtrl = TextEditingController(
    text: widget.identity?.legalMiddleName ?? '',
  );

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    super.dispose();
  }

  String? _validateRequired(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Champ obligatoire.';
    if (value.length > 80) return '80 caractères maximum.';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final middle = _middleNameCtrl.text.trim();
    final ok = await ref
        .read(accountControllerProvider.notifier)
        .saveIdentity(
          userId: widget.userId,
          legalFirstName: _firstNameCtrl.text.trim(),
          legalLastName: _lastNameCtrl.text.trim(),
          legalMiddleName: middle.isEmpty ? null : middle,
        );
    if (!mounted) return;
    final message = ok
        ? 'Identité civile enregistrée.'
        : ref.read(accountControllerProvider).error?.toString() ??
              'Échec de l\'enregistrement.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(accountControllerProvider).isLoading;
    return SettingsSectionCard(
      title: 'Identité civile',
      subtitle:
          'Nom légal, utilisé uniquement pour la vérification de compte — '
          'jamais affiché publiquement.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(labelText: 'Prénom'),
              validator: _validateRequired,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: _validateRequired,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _middleNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Post-nom (optionnel)',
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer l\'identité'),
            ),
          ],
        ),
      ),
    );
  }
}
