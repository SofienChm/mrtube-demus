import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';
import 'package:mrplay_new/features/search/bloc/search_bloc.dart';

class FakeSource implements MusicSource {
  FakeSource({this.id = 'fake', this.pages = const <TrackPage>[], this.error});

  @override
  final String id;

  final List<TrackPage> pages;
  final Object? error;

  final List<String> searchCalls = <String>[];
  final List<String> resolveCalls = <String>[];
  int _callCount = 0;

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
    searchCalls.add(query);
    if (error != null) throw error!;
    if (_callCount < pages.length) return pages[_callCount++];
    // Repeat the last page once exhausted, so a test that searches the same
    // query twice (cache warmup, then a bloc run) still gets results.
    return pages.isEmpty
        ? const TrackPage(items: <Track>[], nextPageToken: null)
        : pages.last;
  }

  @override
  Future<Track> resolve(Track track) async {
    resolveCalls.add(track.id);
    return track;
  }

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

TrackPage pageOf(List<String> ids, {String? next}) => TrackPage(
  items: <Track>[for (final String id in ids) buildTrack(id)],
  nextPageToken: next,
);

void main() {
  late Directory storeDir;
  late DatabaseService database;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrplay_search_test');
    database = await DatabaseService.initAt(storeDir.path);
  });

  tearDown(() async {
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  TrackRepository repositoryFor(MusicSource source) =>
      TrackRepository(database: database, sources: <MusicSource>[source]);

  group('SearchBloc', () {
    test('starts idle with nothing rendered', () async {
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(FakeSource()),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      expect(bloc.state.status, isA<SearchInitial>());
      expect(bloc.state.results, isEmpty);
    });

    test('a committed query with no cache goes loading then success', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a', 'b']),
        ],
      );
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      final List<SearchState> seen = <SearchState>[];
      final sub = bloc.stream.listen(seen.add);
      addTearDown(sub.cancel);

      bloc.add(const SearchQueryCommitted('daft'));
      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchSuccess,
      );

      expect(
        seen.map((SearchState s) => s.status),
        contains(const SearchLoading()),
      );
      expect(bloc.state.results.map((Track t) => t.id), <String>[
        'fake:a',
        'fake:b',
      ]);
      expect(bloc.state.usedCache, isFalse);
    });

    test('an empty result set is reported as empty, not as success', () async {
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(
          FakeSource(pages: <TrackPage>[pageOf(<String>[])]),
        ),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      bloc.add(const SearchQueryCommitted('nothing'));
      await bloc.stream.firstWhere((SearchState s) => s.status is SearchEmpty);

      expect(bloc.state.results, isEmpty);
    });

    test('paints from cache before the network responds', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a']),
        ],
      );
      final TrackRepository repository = repositoryFor(source);

      // Warm the cache with a first, complete search.
      await repository.search('daft');
      final int callsAfterWarmup = source.searchCalls.length;

      final SearchBloc bloc = SearchBloc(
        repository: repository,
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      final List<SearchState> seen = <SearchState>[];
      final sub = bloc.stream.listen(seen.add);
      addTearDown(sub.cancel);

      bloc.add(const SearchQueryCommitted('daft'));
      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchSuccess,
      );

      expect(
        seen.any(
          (SearchState s) =>
              s.status is SearchRefreshing &&
              s.usedCache &&
              s.results.isNotEmpty,
        ),
        isTrue,
        reason: 'cached results must be on screen while the refresh runs',
      );
      expect(
        source.searchCalls.length,
        callsAfterWarmup + 1,
        reason: 'the bloc reconciles with the network even on a cache hit',
      );
    });

    test('keeps cached results when the network fails', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a']),
        ],
      );
      final TrackRepository repository = repositoryFor(source);
      await repository.search('daft');

      // Swap in a failing source while keeping the warm cache.
      final FakeSource failing = FakeSource(
        error: const TransportException('offline'),
      );
      final SearchBloc bloc = SearchBloc(
        repository: TrackRepository(
          database: database,
          sources: <MusicSource>[failing],
        ),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      bloc.add(const SearchQueryCommitted('daft'));
      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchRefreshing && s.usedCache,
      );

      expect(
        bloc.state.results,
        hasLength(1),
        reason: 'losing good cached results to a network error is worse',
      );
      expect(bloc.state.status, isA<SearchRefreshing>());
    });

    test(
      'a quota error degrades to cache-only rather than an error screen',
      () async {
        final FakeSource source = FakeSource(
          pages: <TrackPage>[
            pageOf(<String>['a']),
          ],
        );
        final TrackRepository repository = repositoryFor(source);
        await repository.search('daft');

        final SearchBloc bloc = SearchBloc(
          repository: TrackRepository(
            database: database,
            sources: <MusicSource>[
              FakeSource(
                error: const QuotaExceededException(
                  'Daily search quota exhausted.',
                ),
              ),
            ],
          ),
          debounce: Duration.zero,
        );
        addTearDown(bloc.close);

        bloc.add(const SearchQueryCommitted('daft'));
        await bloc.stream.firstWhere(
          (SearchState s) => s.status is SearchCacheOnly,
        );

        expect(bloc.state.results, hasLength(1));
        expect(bloc.state.status, isA<SearchCacheOnly>());
      },
    );

    test(
      'surfaces a failure when there is nothing cached to fall back on',
      () async {
        final SearchBloc bloc = SearchBloc(
          repository: repositoryFor(
            FakeSource(error: const TransportException('offline')),
          ),
          debounce: Duration.zero,
        );
        addTearDown(bloc.close);

        bloc.add(const SearchQueryCommitted('daft'));
        await bloc.stream.firstWhere(
          (SearchState s) => s.status is SearchFailure,
        );

        expect(bloc.state.status, isA<SearchFailure>());
      },
    );

    test('appends a page and drops ids already in the list', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a', 'b'], next: 'p2'),
          pageOf(<String>['b', 'c']),
        ],
      );
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      bloc.add(const SearchQueryCommitted('daft'));
      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchSuccess,
      );

      bloc.add(const SearchNextPageRequested());
      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchSuccess && s.results.length == 3,
      );

      expect(bloc.state.results.map((Track t) => t.id), <String>[
        'fake:a',
        'fake:b',
        'fake:c',
      ], reason: 'the duplicated id across the page boundary must be dropped');
      expect(bloc.state.hasMore, isFalse);
    });

    test('does not paginate when there is no next page token', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a']),
        ],
      );
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      bloc.add(const SearchQueryCommitted('daft'));
      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchSuccess,
      );

      bloc.add(const SearchNextPageRequested());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(source.searchCalls, hasLength(1));
    });

    test('debounces a burst of keystrokes into a single search', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a']),
        ],
      );
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: const Duration(milliseconds: 40),
      );
      addTearDown(bloc.close);

      bloc.add(const SearchQueryChanged('d'));
      bloc.add(const SearchQueryChanged('da'));
      bloc.add(const SearchQueryChanged('daf'));
      bloc.add(const SearchQueryChanged('daft'));

      await bloc.stream.firstWhere(
        (SearchState s) => s.status is SearchSuccess,
      );

      expect(source.searchCalls, <String>['daft']);
    });

    test('clearing resets the query and cancels any pending search', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['a']),
        ],
      );
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: const Duration(milliseconds: 40),
      );
      addTearDown(bloc.close);

      bloc.add(const SearchQueryChanged('daft'));
      bloc.add(const SearchCleared());

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(bloc.state.query, isEmpty);
      expect(bloc.state.status, isA<SearchInitial>());
      expect(source.searchCalls, isEmpty);
    });

    test('a stale response never overwrites a newer query', () async {
      final FakeSource source = FakeSource(
        pages: <TrackPage>[
          pageOf(<String>['old']),
        ],
      );
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      // Two commits back to back: the first must be discarded as superseded.
      bloc.add(const SearchQueryCommitted('old'));
      bloc.add(const SearchQueryCommitted('new'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.query, 'new');
    });

    test('prefetching a visible viewport warms the source cache', () async {
      final FakeSource source = FakeSource();
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      bloc.add(SearchTrackVisible(<Track>[buildTrack('a'), buildTrack('b')]));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(source.resolveCalls, hasLength(2));
      expect(
        source.searchCalls,
        isEmpty,
        reason: 'prefetch must not re-search',
      );
    });

    test('prefetching the same track twice resolves it once', () async {
      final FakeSource source = FakeSource();
      final SearchBloc bloc = SearchBloc(
        repository: repositoryFor(source),
        debounce: Duration.zero,
      );
      addTearDown(bloc.close);

      bloc.add(SearchTrackVisible(<Track>[buildTrack('a')]));
      bloc.add(SearchTrackVisible(<Track>[buildTrack('a')]));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(source.resolveCalls, <String>['fake:a']);
    });
  });
}
