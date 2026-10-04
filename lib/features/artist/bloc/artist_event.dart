part of 'artist_bloc.dart';

sealed class ArtistEvent extends Equatable {
  const ArtistEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Load the artist's first page. Ignored once tracks are present, so a rebuild
/// cannot restart the request.
final class ArtistLoadRequested extends ArtistEvent {
  const ArtistLoadRequested();
}

/// Load the next page, if there is one.
final class ArtistNextPageRequested extends ArtistEvent {
  const ArtistNextPageRequested();
}
