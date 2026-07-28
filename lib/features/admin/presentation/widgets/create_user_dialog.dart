import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Résultat du dialogue de création d'utilisateur.
class CreateUserResult {
  const CreateUserResult({
    required this.email,
    required this.password,
    required this.username,
    required this.role,
  });

  final String email;
  final String password;
  final String username;
  final String role;
}

/// Dialogue de création d'un utilisateur par un administrateur.
///
/// Permet de choisir l'email, le mot de passe, le nom d'utilisateur et le rôle.
/// L'utilisateur créé pourra se connecter par email+mot de passe OU par Google
/// (s'il utilise la même adresse email).
class CreateUserDialog extends ConsumerStatefulWidget {
  const CreateUserDialog({super.key});

  /// Affiche le dialogue et retourne le résultat, ou `null` si annulé.
  static Future<CreateUserResult?> show(BuildContext context) {
    return showDialog<CreateUserResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateUserDialog(),
    );
  }

  @override
  ConsumerState<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  String _role = 'listener';
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_add_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Créer un utilisateur'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'L\'email est obligatoire.';
                    }
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Email invalide.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Nom d'utilisateur
                TextFormField(
                  controller: _usernameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nom d\'utilisateur',
                    prefixIcon: Icon(Icons.alternate_email),
                    helperText: 'Au moins 4 caractères',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 4) {
                      return 'Minimum 4 caractères.';
                    }
                    if (v.trim().length > 30) {
                      return 'Maximum 30 caractères.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Mot de passe
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'Minimum 8 caractères',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) {
                      return 'Minimum 8 caractères.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Rôle
                Text(
                  'Rôle',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'listener',
                      label: Text('Auditeur'),
                      icon: Icon(Icons.headphones_rounded),
                    ),
                    ButtonSegment(
                      value: 'artist',
                      label: Text('Artiste'),
                      icon: Icon(Icons.mic_rounded),
                    ),
                    ButtonSegment(
                      value: 'admin',
                      label: Text('Admin'),
                      icon: Icon(Icons.admin_panel_settings_rounded),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: (v) => setState(() => _role = v.first),
                  showSelectedIcon: false,
                ),

                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'L\'utilisateur pourra se connecter avec cet email '
                          '+ mot de passe, ou via Google si l\'adresse email '
                          'correspond.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: const Text('Créer le compte'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      CreateUserResult(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        username: _usernameCtrl.text.trim(),
        role: _role,
      ),
    );
  }
}
