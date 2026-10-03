part of 'library_bloc.dart';

sealed class LibraryEvent extends Equatable {
  const LibraryEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Re-reads everything from the database.
final class LibraryFavoritesRequested extends LibraryEvent {
  const LibraryFavoritesRequested();
}

final class LibraryFavoriteToggled extends LibraryEvent {
  const LibraryFavoriteToggled(this.trackId);

  final String trackId;

  @override
  List<Object?> get props => <Object?>[trackId];
}

final class LibraryPlaylistCreated extends LibraryEvent {
  const LibraryPlaylistCreated(this.name, {this.id});

  final String name;
  final String? id;

  @override
  List<Object?> get props => <Object?>[name, id];
}

final class LibraryPlaylistDeleted extends LibraryEvent {
  const LibraryPlaylistDeleted(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class LibraryPlaylistTrackAdded extends LibraryEvent {
  const LibraryPlaylistTrackAdded({
    required this.playlistId,
    required this.trackId,
  });

  final String playlistId;
  final String trackId;

  @override
  List<Object?> get props => <Object?>[playlistId, trackId];
}

final class LibraryPlaylistTrackRemoved extends LibraryEvent {
  const LibraryPlaylistTrackRemoved({
    required this.playlistId,
    required this.trackId,
  });

  final String playlistId;
  final String trackId;

  @override
  List<Object?> get props => <Object?>[playlistId, trackId];
}

final class LibraryHistoryCleared extends LibraryEvent {
  const LibraryHistoryCleared();
}
