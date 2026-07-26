import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_providers.dart';
import 'settings_section_card.dart';

/// Section « Mot de passe ».
///
/// Exigence de longueur alignée sur l'inscription
/// (`auth_screen.dart._validatePassword`) : 6 caractères minimum.
class PasswordSection extends ConsumerStatefulWidget {
  const PasswordSection({super.key});

  @override
  ConsumerState<PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<PasswordSection> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Entre un mot de passe.';
    if (value.length < 6) return '6 caractères minimum.';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _newPasswordCtrl.text) {
      return 'Les mots de passe ne correspondent pas.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(accountControllerProvider.notifier)
        .changePassword(_newPasswordCtrl.text);
    if (!mounted) return;
    final message = ok
        ? 'Mot de passe mis à jour.'
        : ref.read(accountControllerProvider).error?.toString() ??
              'Échec de la mise à jour.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (ok) {
      _newPasswordCtrl.clear();
      _confirmCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(accountControllerProvider).isLoading;
    return SettingsSectionCard(
      title: 'Mot de passe',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _newPasswordCtrl,
              decoration: const InputDecoration(
                labelText: 'Nouveau mot de passe',
              ),
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: _validateNewPassword,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Confirme le mot de passe',
              ),
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: _validateConfirm,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _submit,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Changer le mot de passe'),
            ),
          ],
        ),
      ),
    );
  }
}
