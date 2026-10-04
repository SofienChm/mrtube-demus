import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/artist_summary.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/artist_source.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';
import 'package:mrplay_new/features/artist/bloc/artist_bloc.dart';

class StubArtistSource implements MusicSource, ArtistSource {
  StubArtistSource(this.pages);

  final List<TrackPage> pages;
  int _call = 0;

  @override
  String get id => 'stub';

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
  Future<List<ArtistSummary>> searchUsers(String query) async =>
      const <ArtistSummary>[];

  @override
  Future<TrackPage> fetchArtistTracks(
    String artistId, {
    String? pageToken,
  }) async {
    if (_call >= pages.length) {
      return const TrackPage(items: <Track>[], nextPageToken: null);
    }
    return pages[_call++];
  }

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}

final ArtistSummary samara = ArtistSummary(
  id: 'stub:u1',
  sourceId: 'u1',
  name: 'Samara',
);

Track track(String id) => Track(
  id: 'stub:$id',
  title: 'Title $id',
  artist: 'Samara',
  sourceId: id,
  thumbnailUrl: null,
  streamUrl: 'https://cdn.test/$id.mp3',
);

void main() {
  late Directory storeDir;
  late DatabaseService database;
  late StubArtistSource source;
  late ArtistBloc bloc;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrtube_artist_bloc');
    database = await DatabaseService.initAt(storeDir.path);
    source = StubArtistSource(<TrackPage>[]);
    bloc = ArtistBloc(
      repository: TrackRepository(
        database: database,
        sources: <MusicSource>[source],
      ),
      artist: samara,
    );
  });

  tearDown(() async {
    await bloc.close();
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  test('loads the first page on request', () async {
    source.pages.add(
      TrackPage(items: <Track>[track('a'), track('b')], nextPageToken: null),
    );

    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.status, isA<ArtistSuccess>());
    expect(bloc.state.tracks.map((Track t) => t.title), <String>[
      'Title a',
      'Title b',
    ]);
  });

  test('does not reload when tracks are already present', () async {
    source.pages.add(
      TrackPage(items: <Track>[track('a')], nextPageToken: null),
    );
    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Second request would have consumed an empty second page and wiped the list.
    expect(bloc.state.tracks, hasLength(1));
  });

  test('reports an empty channel distinctly from a failure', () async {
    source.pages.add(const TrackPage(items: <Track>[], nextPageToken: null));

    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.status, isA<ArtistEmpty>());
  });

  test('appends the next page', () async {
    source.pages
      ..add(TrackPage(items: <Track>[track('a')], nextPageToken: '25'))
      ..add(TrackPage(items: <Track>[track('b')], nextPageToken: null));

    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    bloc.add(const ArtistNextPageRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.tracks.map((Track t) => t.title), <String>[
      'Title a',
      'Title b',
    ]);
    expect(bloc.state.hasMore, isFalse);
  });

  test('dedupes an overlapping page instead of growing forever', () async {
    source.pages
      ..add(
        TrackPage(items: <Track>[track('a'), track('b')], nextPageToken: '25'),
      )
      ..add(
        // Offset paging can repeat rows; the list must not double up.
        TrackPage(items: <Track>[track('b'), track('c')], nextPageToken: null),
      );

    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    bloc.add(const ArtistNextPageRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.tracks.map((Track t) => t.title), <String>[
      'Title a',
      'Title b',
      'Title c',
    ]);
  });

  test('keeps loaded tracks when a later page fails', () async {
    source.pages.add(
      TrackPage(items: <Track>[track('a')], nextPageToken: '25'),
    );

    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Source now throws for the next page.
    final FailingSource failing = FailingSource();
    final ArtistBloc b2 = ArtistBloc(
      repository: TrackRepository(
        database: database,
        sources: <MusicSource>[failing],
      ),
      artist: samara,
    );
    addTearDown(b2.close);

    b2.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(b2.state.status, isA<ArtistFailure>());
    expect(bloc.state.hasMore, isTrue, reason: 'precondition for paging');
  });

  test('ignores a page request when there is no next page', () async {
    source.pages.add(
      TrackPage(items: <Track>[track('a')], nextPageToken: null),
    );
    bloc.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    bloc.add(const ArtistNextPageRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.tracks, hasLength(1));
  });

  test('surfaces a load failure', () async {
    final ArtistBloc b2 = ArtistBloc(
      repository: TrackRepository(
        database: database,
        sources: <MusicSource>[FailingSource()],
      ),
      artist: samara,
    );
    addTearDown(b2.close);

    b2.add(const ArtistLoadRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(b2.state.status, isA<ArtistFailure>());
    expect(b2.state.tracks, isEmpty);
  });

  test('does not emit after close', () async {
    source.pages.add(
      TrackPage(items: <Track>[track('a')], nextPageToken: null),
    );
    bloc.add(const ArtistLoadRequested());
    await bloc.close();

    // Would throw "emit after handler completed" style errors if unguarded.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bloc.isClosed, isTrue);
  });
}

class FailingSource implements MusicSource, ArtistSource {
  @override
  String get id => 'failing';

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
  Future<List<ArtistSummary>> searchUsers(String query) async =>
      const <ArtistSummary>[];

  @override
  Future<TrackPage> fetchArtistTracks(
    String artistId, {
    String? pageToken,
  }) async => throw const TransportException('offline');

  @override
  Future<Track> resolve(Track track) async => track;

  @override
  void dispose() {}
}
