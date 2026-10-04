import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/artist_summary.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/artist_source.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';

/// A source with channels.
class FakeArtistSource implements MusicSource, ArtistSource {
  FakeArtistSource({
    this.id = 'fake',
    this.users = const <ArtistSummary>[],
    this.tracks = const <TrackPage>[],
    this.userError,
    this.trackError,
  });

  @override
  final String id;

  final List<ArtistSummary> users;
  final List<TrackPage> tracks;
  final Object? userError;
  final Object? trackError;

  final List<String> userQueries = <String>[];
  final List<String?> artistTrackCalls = <String?>[];
  int _page = 0;

  @override
  bool get supportsDirectAudio => true;

  @override
  bool get searchIsQuotaBound => false;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) async => const TrackPage(items: <Track>[], nextPageToken: null);

  @override
  Future<List<ArtistSummary>> searchUsers(String query) async {
    userQueries.add(query);
    if (userError != null) throw userError!;
    return users;
  }

  @override
  Future<TrackPage> fetchArtistTracks(
    String artistId, {
    String? pageToken,
  }) async {
    artistTrackCalls.add(pageToken);
    if (trackError != null) throw trackError!;
    return _page < tracks.length
        ? tracks[_page++]
        : const TrackPage(items: <Track>[], nextPageToken: null);
  }

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}

/// A source with no channel support at all, which is the common case.
class FakePlainSource implements MusicSource {
  @override
  String get id => 'plain';

  @override
  bool get supportsDirectAudio => false;

  @override
  bool get searchIsQuotaBound => true;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) async => const TrackPage(items: <Track>[], nextPageToken: null);

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}

ArtistSummary artist(String name, {String id = 'u1', int followers = 0}) =>
    ArtistSummary(
      id: 'fake:$id',
      sourceId: id,
      name: name,
      followerCount: followers,
    );

Track track(String id) => Track(
  id: 'fake:$id',
  title: 'Title $id',
  artist: 'Samara',
  sourceId: id,
  thumbnailUrl: null,
  streamUrl: 'https://cdn.test/$id.mp3',
);

void main() {
  late DatabaseService database;
  late Directory storeDir;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrtube_artist_test');
    database = await DatabaseService.initAt(storeDir.path);
  });

  tearDown(() async {
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  group('searchArtists', () {
    test('drops provider noise that does not actually match the query', () {
      final FakeArtistSource source = FakeArtistSource(
        users: <ArtistSummary>[
          artist('Alina Baraz', id: 'a', followers: 87687),
          artist('Samara', id: 'b', followers: 30),
          artist('Mamalarky', id: 'c', followers: 12),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      expect(
        repository.searchArtists('samara'),
        completion(
          isA<List<ArtistSummary>>().having(
            (List<ArtistSummary> a) => a.map((ArtistSummary x) => x.sourceId),
            'ids',
            <String>['b'],
          ),
        ),
      );
    });

    test('ranks a real match above a more popular non-match', () async {
      final FakeArtistSource source = FakeArtistSource(
        users: <ArtistSummary>[
          artist('Alina Baraz', id: 'a', followers: 87687),
          artist('Samara', id: 'b', followers: 30),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      final List<ArtistSummary> found = await repository.searchArtists(
        'samara',
      );
      expect(found.single.sourceId, 'b');
    });

    test('returns empty when no source has channels', () async {
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[FakePlainSource()],
      );

      expect(await repository.searchArtists('samara'), isEmpty);
      expect(repository.artistSources, isEmpty);
    });

    test(
      'returns empty for a blank query without calling the source',
      () async {
        final FakeArtistSource source = FakeArtistSource(
          users: <ArtistSummary>[artist('Samara')],
        );
        final TrackRepository repository = TrackRepository(
          database: database,
          sources: <MusicSource>[source],
        );

        expect(await repository.searchArtists('   '), isEmpty);
        expect(source.userQueries, isEmpty);
      },
    );

    test('throws only when every source fails', () async {
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[
          FakeArtistSource(userError: const TransportException('offline')),
        ],
      );

      expect(repository.searchArtists('samara'), throwsA(isA<AppException>()));
    });

    test('keeps one source results when another source fails', () async {
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[
          FakeArtistSource(
            id: 'broken',
            userError: const TransportException('offline'),
          ),
          FakeArtistSource(
            id: 'working',
            users: <ArtistSummary>[artist('Samara', id: 'b')],
          ),
        ],
      );

      final List<ArtistSummary> found = await repository.searchArtists(
        'samara',
      );
      expect(found.single.sourceId, 'b');
    });

    test('trims the query before hitting the source', () async {
      final FakeArtistSource source = FakeArtistSource();
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      await repository.searchArtists('  samara  ');
      expect(source.userQueries, <String>['samara']);
    });
  });

  group('artistTracks', () {
    test('returns the artist page in provider order', () async {
      final FakeArtistSource source = FakeArtistSource(
        tracks: <TrackPage>[
          TrackPage(
            items: <Track>[track('new'), track('mid')],
            nextPageToken: null,
          ),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      final TrackPage page = await repository.artistTracks(
        artist('Samara', id: 'b'),
      );
      expect(page.items.map((Track t) => t.title), <String>[
        'Title new',
        'Title mid',
      ]);
    });

    test('forwards the page token', () async {
      final FakeArtistSource source = FakeArtistSource(
        tracks: <TrackPage>[
          const TrackPage(items: <Track>[], nextPageToken: '25'),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      await repository.artistTracks(artist('Samara'), pageToken: '25');
      expect(source.artistTrackCalls, <String?>['25']);
    });

    test('caches returned tracks so the player can resolve offline', () async {
      final FakeArtistSource source = FakeArtistSource(
        tracks: <TrackPage>[
          TrackPage(items: <Track>[track('a')], nextPageToken: null),
        ],
      );
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      );

      await repository.artistTracks(artist('Samara'));
      expect(database.getTrack('fake:a'), isNotNull);
    });

    test('throws a clear failure when loading fails', () async {
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[
          FakeArtistSource(trackError: const TransportException('offline')),
        ],
      );

      expect(
        repository.artistTracks(artist('Samara')),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('Samara'),
          ),
        ),
      );
    });

    test('throws when no provider can list the artist', () async {
      final TrackRepository repository = TrackRepository(
        database: database,
        sources: <MusicSource>[FakePlainSource()],
      );

      expect(
        repository.artistTracks(artist('Samara')),
        throwsA(isA<AppException>()),
      );
    });
  });
}
