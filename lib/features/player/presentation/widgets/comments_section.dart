import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/require_auth.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/avatar_circle.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../social/domain/comment.dart';
import '../../../social/presentation/providers/social_providers.dart';
import '../../../social/presentation/widgets/report_sheet.dart';

/// Fil de commentaires paginé d'un clip, avec champ de saisie.
///
/// Vit à l'intérieur du `SingleChildScrollView` du lecteur (mobile : sous les
/// infos du clip ; web large : colonne de droite) — voir `player_screen.dart`.
/// Expose [requestFocus] via un [GlobalKey] pour que la pilule « Commenter »
/// fasse défiler jusqu'ici puis ouvre le clavier sur le champ de saisie.
class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({required this.videoId, super.key});

  final String videoId;

  @override
  ConsumerState<CommentsSection> createState() => CommentsSectionState();
}

class CommentsSectionState extends ConsumerState<CommentsSection> {
  final _bodyController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _replyController = TextEditingController();
  bool _sending = false;
  bool _sendingReply = false;

  /// Id du commentaire racine dont le champ de réponse est ouvert, ou `null`.
  /// Un seul champ de réponse ouvert à la fois.
  String? _replyingToId;

  /// Racines dont les réponses sont dépliées.
  Set<String> _expandedReplies = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    _bodyController.dispose();
    _inputFocusNode.dispose();
    _replyController.dispose();
    super.dispose();
  }

  /// Fait défiler l'écran jusqu'au fil puis ouvre le clavier sur la saisie.
  ///
  /// Appelé par la pilule « Commenter » du lecteur.
  void requestFocus() {
    final ctx = context;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      alignment: 0,
    );
    _inputFocusNode.requestFocus();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(commentsControllerProvider(widget.videoId).notifier).loadMore();
    }
  }

  Future<void> _send() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty || _sending) return;

    // Le champ de saisie reste affiché aux invités : on peut donc arriver ici
    // en ayant fait défiler jusqu'au fil, sans jamais toucher la pilule
    // « Commenter » qui porte déjà la garde. Sans ce contrôle, l'invité
    // recevrait un refus sec du repository au lieu de l'invitation à se
    // connecter.
    if (!await requireAuth(context, ref, gate: AuthGate.comment)) return;
    if (!mounted) return;

    setState(() => _sending = true);

    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(commentsControllerProvider(widget.videoId).notifier)
        .add(body);

    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    } else {
      _bodyController.clear();
    }
  }

  void _startReply(String rootId) {
    _replyController.clear();
    setState(() => _replyingToId = rootId);
  }

  void _cancelReply() {
    _replyController.clear();
    setState(() => _replyingToId = null);
  }

  void _toggleExpandReplies(String rootId) {
    setState(() {
      _expandedReplies = {..._expandedReplies};
      if (!_expandedReplies.add(rootId)) {
        _expandedReplies.remove(rootId);
      }
    });
  }

  /// Envoie une réponse à un commentaire racine — profondeur 1 max, garantie
  /// côté serveur (le bouton « Répondre » n'est de toute façon jamais proposé
  /// sur une réponse, voir `_CommentTile`).
  Future<void> _sendReply(String rootId) async {
    final body = _replyController.text.trim();
    if (body.isEmpty || _sendingReply) return;

    // Même garde que `_send` : le champ de réponse reste accessible à un
    // invité qui aurait fait défiler jusqu'ici.
    if (!await requireAuth(context, ref, gate: AuthGate.comment)) return;
    if (!mounted) return;

    setState(() => _sendingReply = true);

    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(commentsControllerProvider(widget.videoId).notifier)
        .add(body, parentId: rootId);

    if (!mounted) return;
    setState(() => _sendingReply = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    } else {
      _replyController.clear();
      setState(() {
        _replyingToId = null;
        _expandedReplies = {..._expandedReplies, rootId};
      });
    }
  }

  /// Signale un commentaire — même garde que le signalement d'un clip
  /// (`ActionPillsRow._report`), atteignable ici depuis le menu d'une ligne.
  Future<void> _report(String commentId) async {
    if (!await requireAuth(context, ref, gate: AuthGate.report)) return;
    if (!mounted) return;
    await showReportSheet(context, commentId: commentId);
  }

  Future<void> _confirmDelete(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce commentaire ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(commentsControllerProvider(widget.videoId).notifier)
        .remove(commentId);
    if (!mounted || error == null) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commentsAsync = ref.watch(commentsControllerProvider(widget.videoId));
    final currentProfileId = ref
        .watch(currentProfileProvider)
        .asData
        ?.value
        ?.id;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Commentaires',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          commentsAsync.when(
            loading: () => const _CommentsSkeleton(),
            error: (_, _) => ErrorState(
              message: 'Impossible de charger les commentaires.',
              onRetry: () =>
                  ref.invalidate(commentsControllerProvider(widget.videoId)),
            ),
            data: (state) => _CommentsList(
              state: state,
              currentProfileId: currentProfileId,
              onDelete: _confirmDelete,
              onReport: _report,
              expandedReplies: _expandedReplies,
              replyingToId: _replyingToId,
              replyController: _replyController,
              sendingReply: _sendingReply,
              onToggleExpand: _toggleExpandReplies,
              onStartReply: _startReply,
              onCancelReply: _cancelReply,
              onSendReply: _sendReply,
            ),
          ),
          const SizedBox(height: 14),
          _CommentInput(
            controller: _bodyController,
            focusNode: _inputFocusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _CommentsList extends StatelessWidget {
  const _CommentsList({
    required this.state,
    required this.currentProfileId,
    required this.onDelete,
    required this.onReport,
    required this.expandedReplies,
    required this.replyingToId,
    required this.replyController,
    required this.sendingReply,
    required this.onToggleExpand,
    required this.onStartReply,
    required this.onCancelReply,
    required this.onSendReply,
  });

  final CommentsState state;
  final String? currentProfileId;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onReport;
  final Set<String> expandedReplies;
  final String? replyingToId;
  final TextEditingController replyController;
  final bool sendingReply;
  final ValueChanged<String> onToggleExpand;
  final ValueChanged<String> onStartReply;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onSendReply;

  @override
  Widget build(BuildContext context) {
    if (state.comments.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'Aucun commentaire',
        message: 'Sois le premier à réagir à ce clip.',
      );
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in state.comments)
          _CommentTile(
            comment: comment,
            currentProfileId: currentProfileId,
            isExpanded: expandedReplies.contains(comment.id),
            isReplying: replyingToId == comment.id,
            replyController: replyController,
            sendingReply: sendingReply,
            onDelete: onDelete,
            onReport: onReport,
            onToggleExpand: onToggleExpand,
            onStartReply: onStartReply,
            onCancelReply: onCancelReply,
            onSendReply: onSendReply,
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentsSkeleton extends StatelessWidget {
  const _CommentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(
                width: 32,
                height: 32,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(height: 10, width: 120),
                    SizedBox(height: 8),
                    SkeletonBox(height: 10),
                    SizedBox(height: 6),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.5,
                      child: SkeletonBox(height: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un commentaire racine : sa ligne, l'action « Répondre », le repli de ses
/// réponses et le champ de réponse contextuel.
///
/// Le bouton « Répondre » n'apparaît JAMAIS sur une réponse : la profondeur 1
/// est une garantie serveur, l'interface ne doit pas proposer une action qui
/// serait de toute façon rejetée. Les réponses (rendues via [_CommentRow])
/// n'ont donc pas accès à ce bouton.
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.currentProfileId,
    required this.isExpanded,
    required this.isReplying,
    required this.replyController,
    required this.sendingReply,
    required this.onDelete,
    required this.onReport,
    required this.onToggleExpand,
    required this.onStartReply,
    required this.onCancelReply,
    required this.onSendReply,
  });

  final Comment comment;
  final String? currentProfileId;
  final bool isExpanded;
  final bool isReplying;
  final TextEditingController replyController;
  final bool sendingReply;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onReport;
  final ValueChanged<String> onToggleExpand;
  final ValueChanged<String> onStartReply;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onSendReply;

  bool _isOwn(Comment c) =>
      currentProfileId != null && c.authorId == currentProfileId;

  @override
  Widget build(BuildContext context) {
    final replies = comment.replies;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentRow(
            comment: comment,
            isOwn: _isOwn(comment),
            onDelete: () => onDelete(comment.id),
            onReport: () => onReport(comment.id),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => onStartReply(comment.id),
                  child: const Text('Répondre'),
                ),
                if (replies.isNotEmpty)
                  TextButton(
                    onPressed: () => onToggleExpand(comment.id),
                    child: Text(
                      isExpanded
                          ? 'Masquer les réponses'
                          : replies.length == 1
                          ? '1 réponse'
                          : '${replies.length} réponses',
                    ),
                  ),
              ],
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final reply in replies)
                    _CommentRow(
                      comment: reply,
                      isOwn: _isOwn(reply),
                      onDelete: () => onDelete(reply.id),
                      onReport: () => onReport(reply.id),
                    ),
                ],
              ),
            ),
          if (isReplying)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: _ReplyInput(
                controller: replyController,
                sending: sendingReply,
                onCancel: onCancelReply,
                onSend: () => onSendReply(comment.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ligne d'affichage d'un commentaire (racine ou réponse) : avatar, auteur,
/// date, corps, menu contextuel. Ne porte jamais l'action « Répondre » —
/// celle-ci vit uniquement dans [_CommentTile], sur les racines.
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.isOwn,
    required this.onDelete,
    required this.onReport,
  });

  final Comment comment;
  final bool isOwn;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = comment.author;
    final name = author?.resolvedName ?? 'Utilisateur';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarCircle(name: name, avatarPath: author?.avatarPath, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: ArtistNameLabel(
                        name: name,
                        isVerified: author?.isVerified ?? false,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      relativeDate(comment.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (comment.isEdited) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(modifié)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Rendu brut : jamais de HTML/Markdown pour du contenu
                // utilisateur (règle n°9 de CLAUDE.md).
                Text(comment.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          _CommentMenu(isOwn: isOwn, onDelete: onDelete, onReport: onReport),
        ],
      ),
    );
  }
}

class _CommentMenu extends StatelessWidget {
  const _CommentMenu({
    required this.isOwn,
    required this.onDelete,
    required this.onReport,
  });

  final bool isOwn;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: isOwn ? 'Supprimer' : 'Signaler',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      itemBuilder: (context) => [
        if (isOwn)
          PopupMenuItem<void>(
            onTap: onDelete,
            child: const Row(
              children: [
                Icon(Icons.delete_outline_rounded),
                SizedBox(width: 8),
                Text('Supprimer'),
              ],
            ),
          )
        else
          PopupMenuItem<void>(
            onTap: onReport,
            child: const Row(
              children: [
                Icon(Icons.flag_outlined),
                SizedBox(width: 8),
                Text('Signaler'),
              ],
            ),
          ),
      ],
    );
  }
}

class _CommentInput extends StatelessWidget {
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Le clavier ne doit jamais masquer le champ : on ajoute l'espace qu'il
      // occupe en bas, comme le fait déjà `details_step.dart`.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !sending,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ajouter un commentaire…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Envoyer le commentaire',
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Champ de réponse contextuel à un commentaire racine, avec annulation.
class _ReplyInput extends StatelessWidget {
  const _ReplyInput({
    required this.controller,
    required this.sending,
    required this.onCancel,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              enabled: !sending,
              maxLength: 2000,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Répondre…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: 'Annuler la réponse',
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: sending ? null : onCancel,
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Envoyer la réponse',
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
