import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/features/search/data/search_repository.dart';

/// Capture l'URL de la requête générée par le client Postgrest, sans jamais
/// toucher au réseau : on répond directement une liste vide.
///
/// Même technique que celle du paquet `postgrest` pour ses propres tests
/// d'échappement (`filter_escape_test.dart`) : c'est le seul moyen de vérifier
/// le motif `ilike` réellement envoyé, `_sanitize` étant privée.
class _CapturingClient extends http.BaseClient {
  Uri? lastUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUrl = request.url;
    return http.StreamedResponse(
      Stream.value(utf8.encode('[]')),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  late _CapturingClient httpClient;
  late SupabaseClient client;
  late SupabaseSearchRepository repo;

  setUp(() {
    httpClient = _CapturingClient();
    client = SupabaseClient(
      'https://exemple.test',
      'anon-key-de-test',
      httpClient: httpClient,
    );
    repo = SupabaseSearchRepository(client);
  });

  tearDown(() async {
    await client.dispose();
  });

  group('_sanitize (via searchVideos/searchArtists)', () {
    test('échappe les jokers % et _ dans searchVideos', () async {
      await repo.searchVideos('50%_off');

      expect(httpClient.lastUrl, isNotNull);
      expect(
        httpClient.lastUrl!.queryParameters['title'],
        r'ilike.%50\%\_off%',
      );
    });

    test(
      'échappe les antislashs avant % et _ (ordre des remplacements)',
      () async {
        await repo.searchVideos(r'a\b');

        // Un antislash existant est doublé en premier, sinon les remplacements
        // suivants introduiraient de nouveaux antislashs non voulus.
        expect(httpClient.lastUrl!.queryParameters['title'], r'ilike.%a\\b%');
      },
    );

    test(
      'remplace les virgules par des espaces (motif or() de PostgREST)',
      () async {
        await repo.searchArtists('naika,other');

        final orValue = httpClient.lastUrl!.queryParameters['or'];
        expect(orValue, isNotNull);
        expect(orValue, contains('naika other'));
        expect(orValue, isNot(contains(',other')));
      },
    );

    test(
      'une requête de longueur < minQueryLength (2) ne déclenche aucun appel',
      () async {
        final results = await repo.searchVideos('a');

        expect(results, isEmpty);
        expect(httpClient.lastUrl, isNull);
      },
    );

    test(
      'une requête blanche (espaces) après trim est aussi ignorée',
      () async {
        final results = await repo.searchArtists('   ');

        expect(results, isEmpty);
        expect(httpClient.lastUrl, isNull);
      },
    );

    test(
      'une requête de longueur == minQueryLength (2) déclenche bien un appel',
      () async {
        await repo.searchVideos('ab');

        expect(httpClient.lastUrl, isNotNull);
        expect(httpClient.lastUrl!.queryParameters['title'], 'ilike.%ab%');
      },
    );

    test(
      'filtre par genre en plus du titre quand genreId est fourni',
      () async {
        await repo.searchVideos('afro', genreId: 3);

        expect(httpClient.lastUrl!.queryParameters['genre_id'], 'eq.3');
      },
    );

    test('searchArtists ne filtre pas par genre (paramètre absent)', () async {
      await repo.searchArtists('naika');

      expect(
        httpClient.lastUrl!.queryParameters.containsKey('genre_id'),
        isFalse,
      );
      expect(httpClient.lastUrl!.queryParameters['role'], 'eq.artist');
    });

    test('searchVideos ne cible que les clips publiés', () async {
      await repo.searchVideos('afro');

      expect(httpClient.lastUrl!.queryParameters['status'], 'eq.published');
    });
  });
}
