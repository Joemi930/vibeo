import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../../upload/data/thumbnail_picker.dart';
import 'providers/artist_application_providers.dart';
import 'widgets/consent_checkbox.dart';
import 'widgets/id_document_picker.dart';
import 'widgets/security_notice_card.dart';

const int _maxLinks = 5;

/// Formulaire de candidature au statut artiste.
///
/// Redirige déjà vers `/application-status` ou `/studio` depuis le router
/// (`app_router.dart`, garde de `/become-artist`) : cet écran suppose donc
/// que l'utilisateur n'a ni candidature ouverte, ni rôle artiste, mais garde
/// un filet de sécurité en re-vérifiant [myApplicationProvider].
class BecomeArtistScreen extends ConsumerStatefulWidget {
  const BecomeArtistScreen({super.key});

  @override
  ConsumerState<BecomeArtistScreen> createState() => _BecomeArtistScreenState();
}

class _BecomeArtistScreenState extends ConsumerState<BecomeArtistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _stageNameCtrl = TextEditingController();
  final _statementCtrl = TextEditingController();
  final List<TextEditingController> _linkCtrls = [TextEditingController()];

  PickedThumbnail? _document;
  String? _documentFileName;
  bool _consent = false;
  bool _statementTouched = false;

  @override
  void initState() {
    super.initState();
    _statementCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stageNameCtrl.dispose();
    _statementCtrl.dispose();
    for (final ctrl in _linkCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String? _validateStageName(String? v) {
    final value = (v ?? '').trim();
    if (value.length < 2 || value.length > 60) {
      return '2 à 60 caractères.';
    }
    return null;
  }

  String? _validateLink(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Lien invalide (ex. https://...).';
    }
    return null;
  }

  String? _validateStatement(String? v) {
    final value = (v ?? '').trim();
    if (value.length < 30 || value.length > 2000) {
      return '30 à 2000 caractères.';
    }
    return null;
  }

  void _addLinkField() {
    if (_linkCtrls.length >= _maxLinks) return;
    setState(() => _linkCtrls.add(TextEditingController()));
  }

  void _removeLinkField(int index) {
    setState(() {
      final removed = _linkCtrls.removeAt(index);
      removed.dispose();
      if (_linkCtrls.isEmpty) _linkCtrls.add(TextEditingController());
    });
  }

  void _onDocumentError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(() => _statementTouched = true);
    if (!formValid) return;

    if (_document == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une pièce d\'identité.')),
      );
      return;
    }
    if (!_consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu dois accepter les conditions de vérification.'),
        ),
      );
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final links = _linkCtrls
        .map((c) => c.text.trim())
        .where((v) => v.isNotEmpty)
        .toList();

    final ok = await ref
        .read(artistApplicationControllerProvider.notifier)
        .submit(
          userId: user.id,
          stageName: _stageNameCtrl.text.trim(),
          links: links,
          statement: _statementCtrl.text.trim(),
          documentBytes: _document!.bytes,
          documentExtension: _document!.fileExtension,
          documentContentType: _document!.contentType,
        );

    if (!mounted) return;
    if (ok) {
      context.go(AppRoutes.applicationStatus);
      return;
    }
    final error = ref.read(artistApplicationControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'La candidature n\'a pas pu être envoyée.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentRoleProvider);
    final applicationAsync = ref.watch(myApplicationProvider);
    final submitState = ref.watch(artistApplicationControllerProvider);

    // Filet de sécurité derrière la garde du router : si le rôle/la
    // candidature se résolvent après l'affichage initial, on rejoint la bonne
    // destination sans laisser l'utilisateur remplir un formulaire caduc.
    if (role == UserRole.artist || role == UserRole.admin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.studio);
      });
    }
    final openApplication = applicationAsync.asData?.value;
    if (openApplication != null && openApplication.status.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.applicationStatus);
      });
    }

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Devenir artiste'),
      body: applicationAsync.when(
        loading: () => const _BecomeArtistSkeleton(),
        error: (_, _) => Center(
          child: ErrorState(
            message: 'Impossible de vérifier ton statut.',
            onRetry: () => ref.invalidate(myApplicationProvider),
          ),
        ),
        data: (_) => _buildForm(context, submitState),
      ),
    );
  }

  Widget _buildForm(BuildContext context, SubmitApplicationState submitState) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Deviens artiste vérifié pour publier tes clips. Notre '
                'équipe examine chaque demande sous 48 h.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _stageNameCtrl,
                decoration: const InputDecoration(labelText: 'Nom de scène'),
                maxLength: 60,
                textInputAction: TextInputAction.next,
                validator: _validateStageName,
              ),
              const SizedBox(height: 8),
              _LinksSection(
                controllers: _linkCtrls,
                validator: _validateLink,
                onAdd: _addLinkField,
                onRemove: _removeLinkField,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _statementCtrl,
                decoration: InputDecoration(
                  labelText: 'Présentation',
                  helperText:
                      '${_statementCtrl.text.trim().length}/2000 caractères '
                      '(30 minimum)',
                ),
                maxLines: 5,
                maxLength: 2000,
                validator: _validateStatement,
                autovalidateMode: _statementTouched
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
              ),
              const SizedBox(height: 12),
              IdDocumentPicker(
                document: _document,
                fileName: _documentFileName,
                onPick: (picked) => setState(() {
                  _document = picked;
                  _documentFileName = 'Document sélectionné';
                }),
                onError: _onDocumentError,
              ),
              const SizedBox(height: 14),
              const SecurityNoticeCard(
                message:
                    'Document chiffré, visible uniquement par notre équipe '
                    'de vérification, et supprimé automatiquement après la '
                    'décision.',
              ),
              const SizedBox(height: 18),
              ConsentCheckbox(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v),
              ),
              const SizedBox(height: 12),
              GradientButton(
                label: 'Envoyer ma candidature',
                loading: submitState.isSubmitting,
                onPressed: submitState.isSubmitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinksSection extends StatelessWidget {
  const _LinksSection({
    required this.controllers,
    required this.validator,
    required this.onAdd,
    required this.onRemove,
  });

  final List<TextEditingController> controllers;
  final String? Function(String?) validator;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText: i == 0
                          ? 'Liens (Instagram, Spotify…)'
                          : 'Lien ${i + 1}',
                    ),
                    keyboardType: TextInputType.url,
                    validator: validator,
                  ),
                ),
                if (controllers.length > 1)
                  IconButton(
                    tooltip: 'Retirer ce lien',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => onRemove(i),
                  ),
              ],
            ),
          ),
        if (controllers.length < _maxLinks)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un lien'),
            ),
          ),
      ],
    );
  }
}

class _BecomeArtistSkeleton extends StatelessWidget {
  const _BecomeArtistSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SkeletonBox(height: 16, width: 260),
            SizedBox(height: 20),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 56)),
            SizedBox(height: 16),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 56)),
            SizedBox(height: 16),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 120)),
            SizedBox(height: 16),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
