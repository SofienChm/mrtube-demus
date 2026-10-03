part of 'search_bloc.dart';

sealed class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Raw text from the field. Debounced inside the bloc, so the UI can forward
/// every keystroke without throttling itself.
final class SearchQueryChanged extends SearchEvent {
  const SearchQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

/// The debounce window elapsed; time to actually search.
final class SearchQueryCommitted extends SearchEvent {
  const SearchQueryCommitted(this.query);

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

final class SearchCleared extends SearchEvent {
  const SearchCleared();
}

/// Fired when the list nears its end.
final class SearchNextPageRequested extends SearchEvent {
  const SearchNextPageRequested();
}

/// A track card entered the viewport. Warms the cache; never changes state.
final class SearchTrackVisible extends SearchEvent {
  const SearchTrackVisible(this.tracks);

  final List<Track> tracks;

  @override
  List<Object?> get props => <Object?>[tracks];
}

/// Retry after a failure.
final class SearchRetried extends SearchEvent {
  const SearchRetried();
}
