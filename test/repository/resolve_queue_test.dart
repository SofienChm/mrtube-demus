import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';

/// Source whose [resolve] mirrors the real providers: a direct-audio track that
/// already carries a URL resolves without any network work.
class DirectSource implements MusicSource {
  DirectSource({this.unresolvable = const <String>{}});

  final Set<String> unresolvable;
  int resolveCalls = 0;

  @override
  String get id => 'audius';

  @override
  bool get supportsDirectAudio => true;

  @override
  bool get searchIsQuotaBound => false;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) => throw UnimplementedError();

  @override
  Future<Track> resolve(Track track) async {
    resolveCalls++;
    if (unresolvable.contains(track.sourceId)) {
      throw const ContentUnavailableException('gone');
    }
    return track.copyWith(
      streamUrl: 'https://cdn.example/${track.sourceId}.mp3',
    );
  }

  @override
  void dispose() {}
}

/// Embed-only source, standing in for YouTube.
class EmbedSource implements MusicSource {
  @override
  String get id => 'youtube';

  @override
  bool get supportsDirectAudio => false;

  @override
  bool get searchIsQuotaBound => true;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) => throw UnimplementedError();

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}

Track direct(String id) => Track(
  id: 'audius:$id',
  title: 'Title $id',
  artist: 'Artist $id',
  sourceId: id,
  thumbnailUrl: null,
  duration: const Duration(minutes: 3),
);

Track embed(String id) => Track(
  id: 'youtube:$id',
  title: 'Title $id',
  artist: 'Artist $id',
  sourceId: id,
  thumbnailUrl: null,
  playbackCapability: PlaybackCapability.embedOnly,
);

void main() {
  late Directory storeDir;
  late DatabaseService database;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrplay_queue_test');
    database = await DatabaseService.initAt(storeDir.path);
  });

  tearDown(() async {
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  TrackRepository repoFor(List<MusicSource> sources) =>
      TrackRepository(database: database, sources: sources);

  group('TrackRepository.resolveQueue', () {
    test('returns a queue where every entry has a playable URL', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 20; i++) direct('t$i'),
      ];

      final ({List<Track> queue, int startIndex, int nextSourceIndex})?
      resolved = await repository.resolveQueue(tracks, 0, forward: 20);

      expect(resolved, isNotNull);
      for (final Track t in resolved!.queue) {
        expect(
          t.streamUrl,
          isNotNull,
          reason: 'an unresolved entry here is the loadQueue bug',
        );
        expect(t.isDirectAudio, isTrue);
      }
    });

    test('reports where the anchored track now sits', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 20; i++) direct('t$i'),
      ];

      // The default backward window pulls in t2 and t3, so the anchor sits at 2
      // in the resolved queue, not 4.
      final resolved = await repository.resolveQueue(tracks, 4, forward: 20);

      expect(resolved!.startIndex, 2);
      expect(
        resolved.queue[resolved.startIndex].sourceId,
        't4',
        reason: 'passing the old index would start the wrong track',
      );
    });

    test('reports the untouched index when no neighbours precede the anchor', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 20; i++) direct('t$i'),
      ];

      // With no backward window the anchor is the first playable entry, so it
      // legitimately lands at index 0. The queue is rebuilt, not a slice of the
      // original list.
      final resolved = await repository.resolveQueue(
        tracks,
        4,
        back: 0,
        forward: 20,
      );

      expect(resolved!.startIndex, 0);
      expect(resolved.queue.first.sourceId, 't4');
    });

    test('includes a backward window so previous is not a dead end', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 20; i++) direct('t$i'),
      ];

      final resolved = await repository.resolveQueue(
        tracks,
        5,
        back: 2,
        forward: 20,
      );

      expect(resolved!.queue.map((Track t) => t.sourceId).take(3), <String>[
        't3',
        't4',
        't5',
      ]);
      expect(resolved.startIndex, 2);
    });

    test('clamps the backward window at the start of the list', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 5; i++) direct('t$i'),
      ];

      final resolved = await repository.resolveQueue(
        tracks,
        0,
        back: 5,
        forward: 20,
      );

      expect(resolved!.startIndex, 0);
      expect(resolved.queue.first.sourceId, 't0');
    });

    test('drops unplayable entries and remaps the start index', () async {
      final TrackRepository repository = repoFor(<MusicSource>[
        DirectSource(unresolvable: <String>{'t1', 't2'}),
      ]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 20; i++) direct('t$i'),
      ];

      // Anchor at t5. t1 and t2 fall before it in the window and are dropped, so
      // the anchor must shift down by two.
      final resolved = await repository.resolveQueue(
        tracks,
        5,
        back: 5,
        forward: 4,
      );

      // The window covers t0..t9, so growth resumes at t10. Deriving this from
      // queue.length instead would give t8 and re-add tracks already queued.
      expect(resolved!.nextSourceIndex, 10);
      expect(resolved.queue.last.sourceId, 't9');

      final List<String> ids = resolved.queue
          .map((Track t) => t.sourceId)
          .toList();
      expect(ids, isNot(contains('t1')));
      expect(ids, isNot(contains('t2')));
      expect(resolved.queue[resolved.startIndex].sourceId, 't5');
    });

    test('omits neighbours beyond the forward window', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 50; i++) direct('t$i'),
      ];

      final resolved = await repository.resolveQueue(tracks, 0, forward: 5);

      expect(resolved!.queue, hasLength(6));
      expect(resolved.queue.last.sourceId, 't5');
    });

    test('resolves only one round trip before playback can start', () async {
      final DirectSource source = DirectSource();
      final TrackRepository repository = repoFor(<MusicSource>[source]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 50; i++) direct('t$i'),
      ];

      final resolved = await repository.resolveQueue(tracks, 0, forward: 5);

      // Anchor + a bounded window, not all 50.
      expect(source.resolveCalls, lessThan(tracks.length));
      expect(resolved!.queue, hasLength(6));
    });

    test(
      'returns null for an embed-only anchor so the caller falls back',
      () async {
        final TrackRepository repository = repoFor(<MusicSource>[
          EmbedSource(),
        ]);
        final List<Track> tracks = <Track>[
          for (int i = 0; i < 5; i++) embed('v$i'),
        ];

        expect(await repository.resolveQueue(tracks, 0), isNull);
      },
    );

    test('returns null when the anchor cannot be resolved', () async {
      final TrackRepository repository = repoFor(<MusicSource>[
        DirectSource(unresolvable: <String>{'t2'}),
      ]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 5; i++) direct('t$i'),
      ];

      expect(await repository.resolveQueue(tracks, 2), isNull);
    });

    test(
      'returns null for a mixed queue anchored on an embed-only track',
      () async {
        final TrackRepository repository = repoFor(<MusicSource>[
          DirectSource(),
          EmbedSource(),
        ]);
        final List<Track> tracks = <Track>[direct('t0'), embed('v0')];

        expect(await repository.resolveQueue(tracks, 1), isNull);
      },
    );

    test('drops embed-only neighbours from a direct-audio queue', () async {
      final TrackRepository repository = repoFor(<MusicSource>[
        DirectSource(),
        EmbedSource(),
      ]);
      final List<Track> tracks = <Track>[
        direct('t0'),
        embed('v0'),
        direct('t2'),
      ];

      final resolved = await repository.resolveQueue(tracks, 0, forward: 5);

      expect(resolved!.queue.map((Track t) => t.sourceId), <String>[
        't0',
        't2',
      ]);
    });

    test('returns null on an empty list', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      expect(await repository.resolveQueue(<Track>[], 0), isNull);
    });

    test(
      'resolves from cache on a second call without touching the source',
      () async {
        final DirectSource source = DirectSource();
        final TrackRepository repository = repoFor(<MusicSource>[source]);
        final List<Track> tracks = <Track>[
          for (int i = 0; i < 5; i++) direct('t$i'),
        ];

        await repository.resolveQueue(tracks, 0, forward: 5);
        final int afterFirst = source.resolveCalls;

        await repository.resolveQueue(tracks, 0, forward: 5);

        expect(
          source.resolveCalls,
          afterFirst,
          reason: 'resolved tracks are persisted and replayed from cache',
        );
      },
    );
  });

  group('TrackRepository.resolveRange', () {
    test('resolves a slice and omits what it cannot', () async {
      final TrackRepository repository = repoFor(<MusicSource>[
        DirectSource(unresolvable: <String>{'t7'}),
      ]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 10; i++) direct('t$i'),
      ];

      final List<Track> resolved = await repository.resolveRange(
        tracks,
        5,
        limit: 5,
      );

      expect(resolved.map((Track t) => t.sourceId), <String>[
        't5',
        't6',
        't8',
        't9',
      ]);
    });

    test('returns empty past the end of the list', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[direct('t0')];

      expect(await repository.resolveRange(tracks, 5), isEmpty);
      expect(await repository.resolveRange(tracks, 0), hasLength(1));
    });

    test('preserves input order under concurrency', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final List<Track> tracks = <Track>[
        for (int i = 0; i < 20; i++) direct('t$i'),
      ];

      final List<Track> resolved = await repository.resolveRange(
        tracks,
        0,
        limit: 20,
        concurrency: 8,
      );

      // Queue position is user-visible, so reordering would play the wrong track.
      expect(
        resolved.map((Track t) => t.sourceId),
        tracks.map((Track t) => t.sourceId),
      );
    });
  });
}
