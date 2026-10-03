import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';

/// In-memory source so bloc tests never touch HTTP or Hive.
class FakeSource implements MusicSource {
  FakeSource({
    this.id = 'fake',
    this.pages = const <TrackPage>[],
    this.error,
    this.delay = Duration.zero,
  });

  @override
  final String id;

  final List<TrackPage> pages;
  final Object? error;
  final Duration delay;

  final List<String> searchCalls = <String>[];
  int _callCount = 0;

  @override
  bool get supportsDirectAudio => true;

  @override
  bool get searchIsQuotaBound => false;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) async {
    searchCalls.add(query);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return _callCount < pages.length
        ? pages[_callCount++]
        : const TrackPage(items: <Track>[], nextPageToken: null);
  }

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}

Track buildTrack(String id) => Track(
  id: 'fake:$id',
  title: 'Title $id',
  artist: 'Artist $id',
  sourceId: id,
  thumbnailUrl: null,
  duration: const Duration(minutes: 3),
);

void main() {
  late DatabaseService database;
  late Directory storeDir;

  setUp(() async {
    // A fresh directory per test: Hive boxes are process-global, so reusing one
    // path would leak state between tests.
    storeDir = await Directory.systemTemp.createTemp('mrplay_test');
    database = await DatabaseService.initAt(storeDir.path);
  });

  tearDown(() async {
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  group('TrackRepository', () {
    test('searches the source and persists the returned tracks', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          TrackPage(
            items: <Track>[buildTrack('a'), buildTrack('b')],
            nextPageToken: 'p2',
          ),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      final TrackPage page = await repository.search('query');

      expect(page.items, hasLength(2));
      expect(database.getTrack('fake:a'), isNotNull);
      expect(database.getTrack('fake:b'), isNotNull);
      expect(source.searchCalls, <String>['query']);
    });

    test('writes each page through to the cache', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          TrackPage(items: <Track>[buildTrack('a')], nextPageToken: null),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      await repository.search('q');

      // search() is the network path only; the cache-first read that avoids
      // spending quota on a repeat query lives in SearchBloc.
      expect(repository.cachedSearch('q')?.items, hasLength(1));
    });

    test(
      'cachedSearch returns the stored page without calling the source',
      () async {
        final FakeSource source = FakeSource(
          pages: <TrackPage>[
            TrackPage(items: <Track>[buildTrack('a')], nextPageToken: 'p2'),
          ],
        );
        final TrackRepository repository = TrackRepository(
          database: database,
          sources: <MusicSource>[source],
        );

        final TrackPage? first = repository.cachedSearch('cached');
        expect(first, isNull, reason: 'nothing cached yet');

        await repository.search('cached');

        final TrackPage? second = repository.cachedSearch('cached');
        expect(second?.items, hasLength(1));
        expect(second?.nextPageToken, 'p2');
        expect(source.searchCalls, hasLength(1));
      },
    );

    test('falls through to the next source when the first one fails', () async {
      final FakeSource broken = FakeSource(
        id: 'broken',
        error: StateError('boom'),
      );
      final FakeSource working = FakeSource(
        id: 'working',
        pages: <TrackPage>[
          TrackPage(items: <Track>[buildTrack('a')], nextPageToken: null),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[broken, working],
      );

      final TrackPage page = await repository.search('query');

      expect(page.items, hasLength(1));
      expect(working.searchCalls, <String>['query']);
    });

    test('rethrows the failure when every source fails', () async {
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[FakeSource(error: StateError('boom'))],
      );

      // Sources are expected to throw AppException; a raw error is wrapped so
      // callers only ever handle one failure type.
      expect(repository.search('query'), throwsA(isA<TransportException>()));
    });

    test('an expired cache entry triggers a fresh network search', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          TrackPage(items: <Track>[buildTrack('a')], nextPageToken: null),
          TrackPage(items: <Track>[buildTrack('b')], nextPageToken: null),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      await repository.search('q');
      await database.clearMetadataCache();

      await repository.search('q');

      expect(source.searchCalls, hasLength(2));
    });
  });
}
