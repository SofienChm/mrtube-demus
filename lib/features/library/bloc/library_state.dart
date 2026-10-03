part of 'library_bloc.dart';

final class LibraryState extends Equatable {
  const LibraryState({
    this.favoriteIds = const <String>{},
    this.favoriteTracks = const <Track>[],
    this.playlists = const <Playlist>[],
    this.history = const <HistoryEntry>[],
  });

  final Set<String> favoriteIds;
  final List<Track> favoriteTracks;
  final List<Playlist> playlists;
  final List<HistoryEntry> history;

  bool get isEmpty =>
      favoriteTracks.isEmpty && playlists.isEmpty && history.isEmpty;

  bool isFavorite(String trackId) => favoriteIds.contains(trackId);

  /// Tracks for the "recently played" rail, resolved from the local cache.
  ///
  /// History stores ids only, so this hydrates synchronously. Unknown ids are
  /// skipped rather than surfacing a broken row.
  List<Track> historyTracks(DatabaseService database, {int limit = 20}) {
    final List<Track> tracks = <Track>[];
    final Set<String> seen = <String>{};
    for (final HistoryEntry entry in history) {
      if (tracks.length >= limit) break;
      if (!seen.add(entry.trackId)) continue;
      final Track? track = database.getTrack(entry.trackId);
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  LibraryState copyWith({
    Set<String>? favoriteIds,
    List<Track>? favoriteTracks,
    List<Playlist>? playlists,
    List<HistoryEntry>? history,
  }) {
    return LibraryState(
      favoriteIds: favoriteIds ?? this.favoriteIds,
      favoriteTracks: favoriteTracks ?? this.favoriteTracks,
      playlists: playlists ?? this.playlists,
      history: history ?? this.history,
    );
  }

  /// Builds state directly from local storage in one pass.
  factory LibraryState.fromDatabase(DatabaseService database) {
    final Set<String> ids = database.favoriteIds;
    return LibraryState(
      favoriteIds: ids,
      favoriteTracks: database.getTracks(ids.toList(growable: false)),
      playlists: database.playlists,
      history: database.getHistory(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    favoriteIds,
    favoriteTracks,
    playlists,
    history,
  ];
}
