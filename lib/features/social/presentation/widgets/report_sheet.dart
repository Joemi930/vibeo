import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/report_reason.dart';
import '../providers/social_providers.dart';

/// Signature de [submitReport] une fois liée à un `Ref`.
typedef _ReportSubmitter =
    Future<String?> Function({
      String? videoId,
      String? commentId,
      required ReportReason reason,
      String? details,
    });

/// `submitReport` attend un `Ref` (provider), pas le `WidgetRef` d'un widget :
/// ce provider fait le pont en capturant le `Ref` que Riverpod lui fournit à
/// sa création, sans toucher à `social_providers.dart`.
final _reportSubmitterProvider = Provider<_ReportSubmitter>((ref) {
  return ({videoId, commentId, required reason, details}) => submitReport(
    ref,
    videoId: videoId,
    commentId: commentId,
    reason: reason,
    details: details,
  );
});

/// Ouvre la feuille de signalement pour un clip **ou** un commentaire.
///
/// Exactement l'un des deux identifiants doit être fourni.
Future<void> showReportSheet(
  BuildContext context, {
  String? videoId,
  String? commentId,
}) {
  assert(
    (videoId == null) != (commentId == null),
    'showReportSheet : fournis videoId OU commentId, jamais les deux.',
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReportSheet(videoId: videoId, commentId: commentId),
  );
}

/// Feuille glissante de signalement : motif (obligatoire) + détails (facultatif).
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({this.videoId, this.commentId, super.key});

  final String? videoId;
  final String? commentId;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportReason _reason = ReportReason.values.first;
  final _detailsController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);

    // Capturé avant l'appel réseau : cette référence reste valide même après
    // la fermeture de la feuille, contrairement à `context`.
    final messenger = ScaffoldMessenger.of(context);
    final details = _detailsController.text.trim();

    final error = await ref.read(_reportSubmitterProvider)(
      videoId: widget.videoId,
      commentId: widget.commentId,
      reason: _reason,
      details: details.isEmpty ? null : details,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Signalement envoyé. Merci pour ta vigilance.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    widget.commentId != null
                        ? 'Signaler ce commentaire'
                        : 'Signaler ce clip',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choisis le motif qui correspond le mieux.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<ReportReason>(
                    groupValue: _reason,
                    onChanged: _sending
                        ? (_) {}
                        : (value) {
                            if (value != null) {
                              setState(() => _reason = value);
                            }
                          },
                    child: Column(
                      children: [
                        for (final reason in ReportReason.values)
                          RadioListTile<ReportReason>(
                            value: reason,
                            title: Text(reason.label),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _detailsController,
                    enabled: !_sending,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Détails (facultatif)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _sending ? null : _submit,
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Envoyer le signalement'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
