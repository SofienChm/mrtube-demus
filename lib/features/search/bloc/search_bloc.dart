import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/models/artist_summary.dart';
import '../../../core/models/track.dart';
import '../../../core/services/track_repository.dart';
import '../../../core/utils/debouncer.dart';

part 'search_event.dart';
part 'search_state.dart';

/// Drives the search screen: debounced input, cache-first results, pagination,
/// and viewport prefetching.
///
/// Cache-first is the defining behaviour. A committed query paints from local
/// storage synchronously and then reconciles with the network, so the list is
/// never blocked on a request it does not need to wait for.
final class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({
    required this.repository,
    Duration debounce = const Duration(milliseconds: 320),
  }) : super(const SearchState()) {
    on<SearchQueryChanged>(_onQueryChanged, transformer: _droppable());
    on<SearchQueryCommitted>(_onQueryCommitted, transformer: _droppable());
    on<SearchCleared>(_onCleared);
    on<SearchNextPageRequested>(_onNextPage, transformer: _droppable());
    on<SearchTrackVisible>(_onTrackVisible, transformer: _droppable());
    on<SearchRetried>(_onRetried, transformer: _droppable());

    _debouncer = Debouncer(debounce);
  }

  /// How many results to show as autocomplete suggestions.
  static const int _suggestionLimit = 6;

  final TrackRepository repository;
  late final Debouncer _debouncer;

  /// Monotonic token identifying the newest committed query. Responses from
  /// superseded queries are discarded instead of clobbering newer state.
  int _queryGeneration = 0;

  void _onQueryChanged(SearchQueryChanged event, Emitter<SearchState> emit) {
    final String trimmed = event.query.trim();
    if (trimmed.isEmpty) {
      _debouncer.cancel();
      emit(
        state.copyWith(
          status: const SearchInitial(),
          query: '',
          suggestions: const <Track>[],
          results: const <Track>[],
          artists: const <ArtistSummary>[],
          clearPageToken: true,
        ),
      );
      return;
    }

    // Keep the committed result set on screen while the user types; only the
    // suggestion strip reacts immediately.
    emit(state.copyWith(query: event.query));

    _debouncer.run(() {
      if (!isClosed) add(SearchQueryCommitted(trimmed));
    });
  }

  Future<void> _onQueryCommitted(
    SearchQueryCommitted event,
    Emitter<SearchState> emit,
  ) async {
    final String query = event.query.trim();
    if (query.isEmpty) return;

    final int generation = ++_queryGeneration;

    // 1. Paint from cache, if we have it. Synchronous, so the list appears in
    //    the same frame as the keystroke that caused it.
    final TrackPage? cached = repository.cachedSearch(query);
    if (cached != null && cached.items.isNotEmpty) {
      emit(
        SearchState(
          status: const SearchRefreshing(),
          query: query,
          results: cached.items,
          nextPageToken: cached.nextPageToken,
          totalEstimate: cached.totalEstimate,
          usedCache: true,
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: const SearchLoading(),
          query: query,
          results: const <Track>[],
          suggestions: const <Track>[],
          clearPageToken: true,
          usedCache: false,
        ),
      );
    }

    // 2. Reconcile with the network.
    //
    // Artist lookup starts now and in parallel but is awaited last, so the
    // track list is never delayed by it. Its failure is folded into an empty
    // list rather than propagated: a channel row is an enhancement, and letting
    // it fail the whole search would be a worse outcome than omitting it.
    final Future<List<ArtistSummary>> artistsPending = repository
        .searchArtists(query)
        .then<List<ArtistSummary>>(
          (List<ArtistSummary> found) => found,
          onError: (Object _) => const <ArtistSummary>[],
        );

    try {
      final TrackPage page = await repository.search(query);
      if (generation != _queryGeneration || isClosed) return;

      final List<Track> suggestions = page.items
          .take(_suggestionLimit)
          .toList();
      final bool wasCacheOnly = state.status is SearchCacheOnly;

      emit(
        SearchState(
          status: page.items.isEmpty
              ? (wasCacheOnly ? const SearchCacheOnly() : const SearchEmpty())
              : const SearchSuccess(),
          query: query,
          results: page.items,
          suggestions: suggestions,
          nextPageToken: page.nextPageToken,
          totalEstimate: page.totalEstimate,
          usedCache: false,
        ),
      );

      final List<ArtistSummary> artists = await artistsPending;
      if (generation != _queryGeneration || isClosed) return;
      if (artists.isEmpty) return;
      emit(state.copyWith(artists: artists));
    } on AppException catch (error) {
      if (generation != _queryGeneration || isClosed) return;

      final Failure failure = toFailure(error);

      // Keep whatever is already on screen. Losing good cached results to a
      // quota or connectivity error is strictly worse than showing them.
      if (state.results.isNotEmpty) {
        emit(
          state.copyWith(
            status: error is QuotaExceededException
                ? const SearchCacheOnly()
                : const SearchRefreshing(),
            usedCache: true,
          ),
        );
        return;
      }
      emit(state.copyWith(status: SearchFailure(failure)));
    }
  }

  Future<void> _onNextPage(
    SearchNextPageRequested event,
    Emitter<SearchState> emit,
  ) async {
    if (state.isBusy || !state.hasMore) return;

    final int pageIndex = _pageIndexFor(state.results.length);
    emit(state.copyWith(status: const SearchLoadingMore()));

    try {
      final TrackPage page = await repository.search(
        state.query,
        pageToken: state.nextPageToken,
        pageIndex: pageIndex,
      );
      if (isClosed) return;

      // Guard against duplicates: providers occasionally repeat items across
      // page boundaries when the underlying index shifts.
      final Set<String> seen = <String>{
        for (final Track t in state.results) t.id,
      };
      final List<Track> appended = <Track>[
        for (final Track t in page.items)
          if (seen.add(t.id)) t,
      ];

      emit(
        state.copyWith(
          status: const SearchSuccess(),
          results: <Track>[...state.results, ...appended],
          nextPageToken: page.nextPageToken,
          clearPageToken: !page.hasMore,
        ),
      );
    } on AppException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(status: SearchFailure(toFailure(error))));
    }
  }

  void _onTrackVisible(SearchTrackVisible event, Emitter<SearchState> emit) {
    // Fire-and-forget by design: prefetch must not drive rebuilds.
    repository.prefetchAll(event.tracks);
  }

  void _onCleared(SearchCleared event, Emitter<SearchState> emit) {
    _debouncer.cancel();
    _queryGeneration++;
    emit(const SearchState());
  }

  Future<void> _onRetried(
    SearchRetried event,
    Emitter<SearchState> emit,
  ) async {
    if (state.query.isEmpty) return;
    add(SearchQueryCommitted(state.query));
  }

  /// Maps result count to a page index. Providers here return 25 per page.
  static int _pageIndexFor(int resultCount) => resultCount ~/ 25;

  /// Serialises events per handler so a burst of keystrokes cannot interleave
  /// two in-flight searches.
  static EventTransformer<E> _droppable<E>() =>
      (Stream<E> events, EventMapper<E> mapper) => events.asyncExpand(mapper);

  @override
  Future<void> close() {
    _debouncer.dispose();
    return super.close();
  }
}
