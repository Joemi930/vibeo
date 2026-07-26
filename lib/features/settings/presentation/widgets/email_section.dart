import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_providers.dart';
import 'settings_section_card.dart';

/// Section « Adresse email ».
///
/// `supabase.auth.updateUser` envoie un mail de confirmation à la **nouvelle**
/// adresse : le changement n'est effectif qu'après clic sur ce lien, et
/// l'adresse actuelle reste valide entre-temps — l'utilisateur doit le savoir
/// avant de valider, sans quoi il croirait l'action instantanée.
class EmailSection extends ConsumerStatefulWidget {
  const EmailSection({required this.currentEmail, super.key});

  final String? currentEmail;

  @override
  ConsumerState<EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends ConsumerState<EmailSection> {
  final _formKey = GlobalKey<FormState>();
  late final _emailCtrl = TextEditingController(text: widget.currentEmail);

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Entre un email.';
    final re = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w\-.]+$');
    if (!re.hasMatch(value)) return 'Email invalide.';
    if (value == widget.currentEmail) {
      return 'C\'est déjà ton adresse actuelle.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final newEmail = _emailCtrl.text.trim();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Changer d\'email'),
        content: Text(
          'Un email de confirmation va être envoyé à $newEmail. '
          'Le changement ne sera effectif qu\'après avoir cliqué sur le lien '
          'reçu ; ton adresse actuelle reste active jusque-là.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer la confirmation'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await ref
        .read(accountControllerProvider.notifier)
        .changeEmail(newEmail);
    if (!mounted) return;
    final message = ok
        ? 'Email de confirmation envoyé à $newEmail.'
        : ref.read(accountControllerProvider).error?.toString() ??
              'Échec de l\'envoi.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(accountControllerProvider).isLoading;
    return SettingsSectionCard(
      title: 'Adresse email',
      subtitle: 'Un mail de confirmation part sur la nouvelle adresse.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
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
                  : const Text('Changer d\'email'),
            ),
          ],
        ),
      ),
    );
  }
}
