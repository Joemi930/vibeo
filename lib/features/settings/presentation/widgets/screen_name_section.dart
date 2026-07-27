import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/profile.dart';
import '../providers/account_providers.dart';
import 'settings_section_card.dart';

/// Section « Nom de scène et nom d'utilisateur ».
///
/// `display_name` (nom de scène, affiché) et `username` (identifiant unique,
/// utilisé dans les liens `@handle`) vivent tous deux sur `profiles` — table
/// publique, à la différence de l'identité civile.
class ScreenNameSection extends ConsumerStatefulWidget {
  const ScreenNameSection({required this.profile, super.key});

  final Profile profile;

  @override
  ConsumerState<ScreenNameSection> createState() => _ScreenNameSectionState();
}

class _ScreenNameSectionState extends ConsumerState<ScreenNameSection> {
  final _formKey = GlobalKey<FormState>();
  late final _displayNameCtrl = TextEditingController(
    text: widget.profile.displayName ?? '',
  );
  late final _usernameCtrl = TextEditingController(
    text: widget.profile.username,
  );

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  String? _validateUsername(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Choisis un nom d\'utilisateur.';
    if (value.length < 4) return '4 caractères minimum.';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final displayName = _displayNameCtrl.text.trim();
    final ok = await ref
        .read(accountControllerProvider.notifier)
        .updateScreenName(
          userId: widget.profile.id,
          displayName: displayName.isEmpty ? null : displayName,
          username: _usernameCtrl.text.trim(),
        );
    if (!mounted) return;
    final message = ok
        ? 'Nom de scène et nom d\'utilisateur mis à jour.'
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
      title: 'Nom de scène et nom d\'utilisateur',
      subtitle: 'Visibles publiquement sur ton profil et tes clips.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(labelText: 'Nom de scène'),
              maxLength: 50,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom d\'utilisateur',
                prefixText: '@',
              ),
              validator: _validateUsername,
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
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
