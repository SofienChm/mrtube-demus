import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/artist_summary.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/artist_source.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';
import 'package:mrplay_new/features/search/bloc/search_bloc.dart';

/// Serves both tracks and artist channels, and can fail each independently.
class SourceWithArtists implements MusicSource, ArtistSource {
  SourceWithArtists({
    this.pages = const <TrackPage>[],
    this.users = const <ArtistSummary>[],
    this.trackError,
    this.userError,
    this.userDelay = Duration.zero,
  });

  final List<TrackPage> pages;
  final List<ArtistSummary> users;
  final Object? trackError;
  final Object? userError;
  final Duration userDelay;

  int _call = 0;

  @override
  String get id => 'withartists';

  @override
  bool get supportsDirectAudio => true;

  @override
  bool get searchIsQuotaBound => true;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) async {
    if (trackError != null) throw trackError!;
    if (_call < pages.length) return pages[_call++];
    return const TrackPage(items: <Track>[], nextPageToken: null);
  }

  @override
  Future<List<ArtistSummary>> searchUsers(String query) async {
    if (userDelay > Duration.zero) await Future<void>.delayed(userDelay);
    if (userError != null) throw userError!;
    return users;
  }

  @override
  Future<TrackPage> fetchArtistTracks(
    String artistId, {
    String? pageToken,
  }) async => const TrackPage(items: <Track>[], nextPageToken: null);

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}

Track track(String id, {String artist = 'Samara'}) => Track(
  id: 'wa:$id',
  title: 'Title $id',
  artist: artist,
  sourceId: id,
  thumbnailUrl: null,
  streamUrl: 'https://cdn.test/$id.mp3',
);

void main() {
  late Directory storeDir;
  late DatabaseService database;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrtube_search_artist');
    database = await DatabaseService.initAt(storeDir.path);
  });

  tearDown(() async {
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  SearchBloc blocFor(List<MusicSource> sources) => SearchBloc(
    repository: TrackRepository(database: database, sources: sources),
    debounce: const Duration(milliseconds: 1),
  );

  test('puts matched channels into the state', () async {
    final SearchBloc bloc = blocFor(<MusicSource>[
      SourceWithArtists(
        pages: <TrackPage>[
          TrackPage(items: <Track>[track('a')], nextPageToken: null),
        ],
        users: <ArtistSummary>[
          ArtistSummary(id: 'wa:b', sourceId: 'b', name: 'Samara'),
        ],
      ),
    ]);
    addTearDown(bloc.close);

    bloc.add(const SearchQueryCommitted('samara'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(bloc.state.status, isA<SearchSuccess>());
    expect(bloc.state.artists.map((ArtistSummary a) => a.name), <String>[
      'Samara',
    ]);
  });

  test('still shows tracks when channel lookup fails', () async {
    // The channel row is an enhancement; losing it must never empty the results.
    final SearchBloc bloc = blocFor(<MusicSource>[
      SourceWithArtists(
        pages: <TrackPage>[
          TrackPage(items: <Track>[track('a')], nextPageToken: null),
        ],
        userError: const TransportException('offline'),
      ),
    ]);
    addTearDown(bloc.close);

    bloc.add(const SearchQueryCommitted('samara'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(bloc.state.status, isA<SearchSuccess>());
    expect(bloc.state.results, hasLength(1));
    expect(bloc.state.artists, isEmpty);
  });

  test('shows tracks before a slow channel lookup resolves', () async {
    final SearchBloc bloc = blocFor(<MusicSource>[
      SourceWithArtists(
        pages: <TrackPage>[
          TrackPage(items: <Track>[track('a')], nextPageToken: null),
        ],
        users: <ArtistSummary>[
          ArtistSummary(id: 'wa:b', sourceId: 'b', name: 'Samara'),
        ],
        userDelay: const Duration(milliseconds: 300),
      ),
    ]);
    addTearDown(bloc.close);

    bloc.add(const SearchQueryCommitted('samara'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // Tracks must not be held hostage to the channel request.
    expect(bloc.state.results, hasLength(1));
    expect(bloc.state.artists, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(bloc.state.artists, hasLength(1));
  });

  test('clears channels when the query is cleared', () async {
    final SearchBloc bloc = blocFor(<MusicSource>[
      SourceWithArtists(
        pages: <TrackPage>[
          TrackPage(items: <Track>[track('a')], nextPageToken: null),
        ],
        users: <ArtistSummary>[
          ArtistSummary(id: 'wa:b', sourceId: 'b', name: 'Samara'),
        ],
      ),
    ]);
    addTearDown(bloc.close);

    bloc.add(const SearchQueryCommitted('samara'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(bloc.state.artists, isNotEmpty);

    bloc.add(const SearchCleared());
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(bloc.state.artists, isEmpty);
  });

  test('does not attach a stale channel to a newer query', () async {
    final SearchBloc bloc = blocFor(<MusicSource>[
      SourceWithArtists(
        pages: <TrackPage>[
          TrackPage(items: <Track>[track('a')], nextPageToken: null),
        ],
        users: <ArtistSummary>[
          ArtistSummary(id: 'wa:b', sourceId: 'b', name: 'Samara'),
        ],
        userDelay: const Duration(milliseconds: 250),
      ),
    ]);
    addTearDown(bloc.close);

    bloc.add(const SearchQueryCommitted('samara'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    bloc.add(const SearchCleared());
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      bloc.state.artists,
      isEmpty,
      reason: 'a late channel response must not repopulate a cleared search',
    );
  });

  test(
    'drops provider noise so a stranger is not shown as the channel',
    () async {
      final SearchBloc bloc = blocFor(<MusicSource>[
        SourceWithArtists(
          pages: <TrackPage>[
            TrackPage(items: <Track>[track('a')], nextPageToken: null),
          ],
          users: <ArtistSummary>[
            ArtistSummary(
              id: 'wa:a',
              sourceId: 'a',
              name: 'Alina Baraz',
              followerCount: 87687,
            ),
            ArtistSummary(id: 'wa:b', sourceId: 'b', name: 'Samara'),
          ],
        ),
      ]);
      addTearDown(bloc.close);

      bloc.add(const SearchQueryCommitted('samara'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bloc.state.artists.map((ArtistSummary a) => a.name), <String>[
        'Samara',
      ]);
    },
  );
}
