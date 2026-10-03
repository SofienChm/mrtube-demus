import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/playlist.dart';
import '../../../core/models/track.dart';
import '../../../core/services/database_service.dart';

part 'library_event.dart';
part 'library_state.dart';

/// Owns everything the user has created or accumulated locally: favorites,
/// playlists, and listening history.
///
/// State is rebuilt from the synchronous Hive reads in [DatabaseService] after
/// every mutation. That keeps the bloc free of duplicate bookkeeping and means
/// a cache clear or an external write can never leave the UI showing something
/// the database does not agree with.
final class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  LibraryBloc({required DatabaseService database})
    : _database = database,
      super(LibraryState.fromDatabase(database)) {
    on<LibraryFavoritesRequested>(_onReload);
    on<LibraryFavoriteToggled>(_onFavoriteToggled, transformer: _sequential());
    on<LibraryPlaylistCreated>(_onPlaylistCreated, transformer: _sequential());
    on<LibraryPlaylistDeleted>(_onPlaylistDeleted, transformer: _sequential());
    on<LibraryPlaylistTrackAdded>(
      _onPlaylistTrackAdded,
      transformer: _sequential(),
    );
    on<LibraryPlaylistTrackRemoved>(
      _onPlaylistTrackRemoved,
      transformer: _sequential(),
    );
    on<LibraryHistoryCleared>(_onHistoryCleared, transformer: _sequential());
  }

  final DatabaseService _database;

  static EventTransformer<E> _sequential<E>() =>
      (Stream<E> events, EventMapper<E> mapper) => events.asyncExpand(mapper);

  void _onReload(LibraryFavoritesRequested event, Emitter<LibraryState> emit) {
    emit(LibraryState.fromDatabase(_database));
  }

  Future<void> _onFavoriteToggled(
    LibraryFavoriteToggled event,
    Emitter<LibraryState> emit,
  ) async {
    // Optimistic: flip in state first so the heart fills on the same frame as
    // the tap, then persist. Rolled back below if the write fails.
    final bool next = !state.favoriteIds.contains(event.trackId);
    emit(
      next
          ? state.copyWith(
              favoriteIds: <String>{...state.favoriteIds, event.trackId},
            )
          : state.copyWith(
              favoriteIds: <String>{...state.favoriteIds}
                ..remove(event.trackId),
            ),
    );

    try {
      await _database.setFavorite(event.trackId, next);
    } on Object {
      emit(
        next
            ? state.copyWith(
                favoriteIds: <String>{...state.favoriteIds}
                  ..remove(event.trackId),
              )
            : state.copyWith(
                favoriteIds: <String>{...state.favoriteIds, event.trackId},
              ),
      );
      return;
    }

    // Reconcile from storage so `favoriteTracks` (not just the id set) reflects
    // the write. The optimistic emit above only had the id to work with.
    emit(LibraryState.fromDatabase(_database));
  }

  Future<void> _onPlaylistCreated(
    LibraryPlaylistCreated event,
    Emitter<LibraryState> emit,
  ) async {
    final DateTime now = DateTime.now();
    final Playlist playlist = Playlist(
      id: event.id ?? 'pl_${now.microsecondsSinceEpoch}',
      name: event.name,
      trackIds: const <String>[],
      createdAt: now,
      updatedAt: now,
      pendingSync: true,
    );
    await _database.putPlaylist(playlist);
    emit(LibraryState.fromDatabase(_database));
  }

  Future<void> _onPlaylistDeleted(
    LibraryPlaylistDeleted event,
    Emitter<LibraryState> emit,
  ) async {
    await _database.deletePlaylist(event.id);
    emit(LibraryState.fromDatabase(_database));
  }

  Future<void> _onPlaylistTrackAdded(
    LibraryPlaylistTrackAdded event,
    Emitter<LibraryState> emit,
  ) async {
    final Playlist? playlist = _database.getPlaylist(event.playlistId);
    if (playlist == null) return;
    if (playlist.trackIds.contains(event.trackId)) return;

    await _database.putPlaylist(
      playlist.copyWith(
        trackIds: <String>[...playlist.trackIds, event.trackId],
        updatedAt: DateTime.now(),
        pendingSync: true,
      ),
    );
    emit(LibraryState.fromDatabase(_database));
  }

  Future<void> _onPlaylistTrackRemoved(
    LibraryPlaylistTrackRemoved event,
    Emitter<LibraryState> emit,
  ) async {
    final Playlist? playlist = _database.getPlaylist(event.playlistId);
    if (playlist == null) return;

    await _database.putPlaylist(
      playlist.copyWith(
        trackIds: <String>[
          for (final String id in playlist.trackIds)
            if (id != event.trackId) id,
        ],
        updatedAt: DateTime.now(),
        pendingSync: true,
      ),
    );
    emit(LibraryState.fromDatabase(_database));
  }

  Future<void> _onHistoryCleared(
    LibraryHistoryCleared event,
    Emitter<LibraryState> emit,
  ) async {
    await _database.clearHistory();
    emit(LibraryState.fromDatabase(_database));
  }
}
