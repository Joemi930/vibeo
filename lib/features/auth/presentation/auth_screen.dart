import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/theme_toggle_switch.dart';
import '../../../core/widgets/vibeo_logo.dart';
import 'providers/auth_controller.dart';
import 'providers/guest_mode_provider.dart';
import 'widgets/google_button.dart';

/// Écran d'authentification : bascule Connexion / Inscription, email + mot de
/// passe, mot de passe oublié, connexion Google, mode invité. Fidèle à
/// `Maquettes/Auth.dc.html`.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({this.returnTo, super.key});

  /// Destination à rejoindre après connexion, quand l'utilisateur a été
  /// redirigé ici depuis une page réservée aux membres.
  final String? returnTo;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { signIn, signUp }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == _AuthMode.signUp;

  void _switchMode(_AuthMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
  }

  String? _validateEmail(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Entre ton email.';
    final re = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w\-.]+$');
    if (!re.hasMatch(value)) return 'Email invalide.';
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Entre ton mot de passe.';
    if (value.length < 6) return '6 caractères minimum.';
    return null;
  }

  String? _validateUsername(String? v) {
    if (!_isSignUp) return null;
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Choisis un nom d\'utilisateur.';
    if (value.length < 4) return '4 caractères minimum.';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);

    if (_isSignUp) {
      final outcome = await controller.signUp(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        username: _usernameCtrl.text,
      );
      if (!mounted || outcome == null) return;
      if (outcome.needsEmailConfirmation) {
        context.push(
          AppRoutes.emailVerification,
          extra: _emailCtrl.text.trim(),
        );
      }
    } else {
      final ok = await controller.signIn(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted || !ok) return;
      // On quitte le mode invité et on revient à l'endroit exact d'où
      // l'utilisateur a été redirigé (la garde du router vise la même cible).
      await ref.read(guestModeProvider.notifier).disable();
      if (!mounted) return;
      // Toujours passer par le filtre anti-redirection ouverte : `returnTo`
      // vient de l'URL et n'est donc pas digne de confiance.
      context.go(AppRoutes.sanitizeReturnTo(widget.returnTo));
    }
  }

  /// Entre en mode invité : consultation libre, sans compte.
  Future<void> _continueAsGuest() async {
    await ref.read(guestModeProvider.notifier).enable();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailCtrl.text),
    );
    if (email == null || !mounted) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(email);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email de réinitialisation envoyé si le compte existe.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isLoading;

    // Affiche les erreurs d'auth via SnackBar.
    ref.listen(authControllerProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next.error.toString()),
              backgroundColor: theme.colorScheme.error,
            ),
          );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Bascule de thème accessible dès l'écran d'accueil de l'app.
            const Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: ThemeToggleSwitch(),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        const Center(child: VibeoLogo(size: 58)),
                        const SizedBox(height: 18),
                        Text(
                          'Bienvenue sur Vibeo',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Les clips de tes artistes préférés, vérifiés.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _ModeToggle(mode: _mode, onChanged: _switchMode),
                        const SizedBox(height: 22),
                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _usernameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom d\'utilisateur',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newUsername],
                            validator: _validateUsername,
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                              tooltip: _obscure ? 'Afficher' : 'Masquer',
                            ),
                          ),
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          validator: _validatePassword,
                        ),
                        if (!_isSignUp) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: loading ? null : _forgotPassword,
                              child: const Text('Mot de passe oublié ?'),
                            ),
                          ),
                        ] else
                          const SizedBox(height: 20),
                        const SizedBox(height: 14),
                        GradientButton(
                          label: _isSignUp
                              ? 'Créer mon compte'
                              : 'Se connecter',
                          loading: loading,
                          onPressed: loading ? null : _submit,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'ou',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 18),
                        GoogleButton(
                          onPressed: loading
                              ? null
                              : () => ref
                                    .read(authControllerProvider.notifier)
                                    .signInWithGoogle(),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: loading ? null : _continueAsGuest,
                          icon: const Icon(Icons.explore_outlined, size: 20),
                          label: const Text('Continuer en tant qu\'invité'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tu pourras regarder les clips librement. Un compte est '
                          'nécessaire pour aimer, commenter ou t\'abonner.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'En continuant, tu acceptes nos Conditions d\'utilisation '
                          'et notre Politique de confidentialité.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bascule segmentée Connexion / Inscription (onglet actif au dégradé).
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _segment(context, 'Connexion', _AuthMode.signIn),
          _segment(context, 'Inscription', _AuthMode.signUp),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, _AuthMode value) {
    final theme = Theme.of(context);
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? _gradient : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected
                  ? Colors.white
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  static const LinearGradient _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
  );
}

/// Boîte de dialogue de saisie d'email pour la réinitialisation du mot de passe.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});
  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialEmail,
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mot de passe oublié'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) return 'Entre ton email.';
            if (!RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w\-.]+$').hasMatch(value)) {
              return 'Email invalide.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _ctrl.text.trim());
            }
          },
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}
