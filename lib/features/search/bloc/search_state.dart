part of 'search_bloc.dart';

/// Status of the result list. Modelled as a sealed hierarchy so the UI can
/// exhaustively switch and never accidentally treat `loading` as `empty`.
sealed class SearchStatus extends Equatable {
  const SearchStatus();

  @override
  List<Object?> get props => const <Object?>[];
}

final class SearchInitial extends SearchStatus {
  const SearchInitial();
}

/// A network request is in flight and no cached page exists to show yet.
final class SearchLoading extends SearchStatus {
  const SearchLoading();
}

/// Cached results are on screen while a refresh runs behind them. This is the
/// state that keeps repeat searches feeling instant.
final class SearchRefreshing extends SearchStatus {
  const SearchRefreshing();
}

/// Results loaded from cache only, with no network attempt pending. Produced
/// when quota is exhausted or the device is offline.
final class SearchCacheOnly extends SearchStatus {
  const SearchCacheOnly();
}

/// A page was appended to an existing result set.
final class SearchLoadingMore extends SearchStatus {
  const SearchLoadingMore();
}

final class SearchSuccess extends SearchStatus {
  const SearchSuccess();
}

final class SearchEmpty extends SearchStatus {
  const SearchEmpty();
}

final class SearchFailure extends SearchStatus {
  const SearchFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

final class SearchState extends Equatable {
  const SearchState({
    this.status = const SearchInitial(),
    this.query = '',
    this.results = const <Track>[],
    this.suggestions = const <Track>[],
    this.artists = const <ArtistSummary>[],
    this.nextPageToken,
    this.totalEstimate,
    this.usedCache = false,
  });

  final SearchStatus status;
  final String query;

  /// Full accumulated result set. Appended in place for pagination, so the list
  /// identity changes only when content does.
  final List<Track> results;

  /// Autocomplete suggestions for the in-progress query. Kept separate from
  /// [results] so typing does not thrash the main list.
  final List<Track> suggestions;

  /// Artist/channel accounts matching [query], ranked by name match rather than
  /// by the provider's own ordering.
  ///
  /// Separate from [results] because they come from a different endpoint with
  /// different failure modes: a channel lookup that fails must not empty the
  /// track list.
  final List<ArtistSummary> artists;

  final String? nextPageToken;
  final int? totalEstimate;

  /// True when the visible results came from local storage, so the UI can show
  /// an offline/cache indicator.
  final bool usedCache;

  bool get hasMore => nextPageToken != null && nextPageToken!.isNotEmpty;

  bool get isBusy =>
      status is SearchLoading ||
      status is SearchRefreshing ||
      status is SearchLoadingMore;

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<Track>? results,
    List<Track>? suggestions,
    List<ArtistSummary>? artists,
    String? nextPageToken,
    int? totalEstimate,
    bool? usedCache,
    bool clearPageToken = false,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      suggestions: suggestions ?? this.suggestions,
      artists: artists ?? this.artists,
      nextPageToken: clearPageToken
          ? null
          : (nextPageToken ?? this.nextPageToken),
      totalEstimate: totalEstimate ?? this.totalEstimate,
      usedCache: usedCache ?? this.usedCache,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    query,
    results,
    suggestions,
    artists,
    nextPageToken,
    totalEstimate,
    usedCache,
  ];
}
