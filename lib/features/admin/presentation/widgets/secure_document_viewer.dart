import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/dev_log.dart';
import '../providers/admin_providers.dart';

/// Visionneuse de document d'identité avec lien signé à durée limitée.
///
/// Appelle `adminRepository.documentUrl(applicationId)` pour obtenir une URL
/// signée de 5 minutes. Un compte à rebours affiche le temps restant ; à
/// expiration, l'image est vidée du cache et le lien est inutilisable.
/// L'admin peut « Réémettre le lien » pour obtenir une nouvelle URL.
class SecureDocumentViewer extends ConsumerStatefulWidget {
  const SecureDocumentViewer({required this.applicationId, super.key});

  final String applicationId;

  @override
  ConsumerState<SecureDocumentViewer> createState() =>
      _SecureDocumentViewerState();
}

class _SecureDocumentViewerState extends ConsumerState<SecureDocumentViewer> {
  String? _imageUrl;
  bool _loading = false;
  String? _error;
  Timer? _countdownTimer;
  DateTime? _expiryTime;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _evictCachedImage();
    super.dispose();
  }

  void _evictCachedImage() {
    if (_imageUrl != null) {
      imageCache.evict(NetworkImage(_imageUrl!));
    }
  }

  Future<void> _fetchUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(adminRepositoryProvider)
          .documentUrl(widget.applicationId);
      if (!mounted) return;
      _evictCachedImage();
      setState(() {
        _imageUrl = result.url;
        _loading = false;
      });
      _startCountdown(result.expiresIn);
    } catch (e) {
      logError('SecureDocumentViewer : impossible d\'obtenir l\'URL signée', e);
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger le document.';
        _loading = false;
      });
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _expiryTime = DateTime.now().add(Duration(seconds: seconds));
    _remaining = Duration(seconds: seconds);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        return;
      }
      final diff = _expiryTime!.difference(DateTime.now());
      if (diff.isNegative) {
        _expire();
      } else {
        setState(() => _remaining = diff);
      }
    });
  }

  void _expire() {
    _countdownTimer?.cancel();
    _evictCachedImage();
    if (!mounted) return;
    setState(() {
      _imageUrl = null;
      _remaining = Duration.zero;
      _error = 'Le lien a expiré. Réémets-le pour continuer.';
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    // Chargement automatique à l'ouverture du panneau.
    _fetchUrl();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bandeau « Accès sécurisé — lien expirant dans … »
        if (_imageUrl != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              border: Border.all(color: theme.colorScheme.error),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_clock_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _remaining.inSeconds > 0
                        ? 'Accès sécurisé — lien expirant dans'
                        : 'Accès sécurisé — lien expiré',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                Text(
                  _formatDuration(_remaining),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'Space Mono',
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),

        // Libellé de section
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Document d\'identité',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        // Zone d'affichage du document
        if (_loading)
          Container(
            height: 172,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (_imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 172,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    child: Image.network(
                      _imageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return _buildFallback(context, 'Échec du chargement');
                      },
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_error != null)
          Container(
            height: 172,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
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

        // Bouton « Réémettre le lien »
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loading ? null : _fetchUrl,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              _imageUrl != null ? 'Réémettre le lien' : 'Obtenir le lien',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallback(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.badge_outlined,
            size: 30,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
