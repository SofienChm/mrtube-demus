import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/models/playlist.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/features/library/bloc/library_bloc.dart';

/// Waits until a state predicate holds.
///
/// Bloc handlers await real Hive I/O, which `pumpEventQueue` does not drain, so
/// polling is the only reliable way to observe the settled state. Polling also
/// tolerates handlers that correctly emit nothing (a no-op add).
Future<void> until(
  LibraryBloc bloc,
  bool Function(LibraryState state) predicate,
) async {
  for (int i = 0; i < 400; i++) {
    if (predicate(bloc.state)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('state never satisfied the predicate: ${bloc.state}');
}

Track buildTrack(String id) => Track(
  id: 'fake:$id',
  title: 'Title $id',
  artist: 'Artist $id',
  sourceId: id,
  thumbnailUrl: null,
  duration: const Duration(minutes: 3),
);

void main() {
  late Directory storeDir;
  late DatabaseService database;
  late LibraryBloc bloc;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrplay_library_test');
    database = await DatabaseService.initAt(storeDir.path);
    await database.putTracks(<Track>[buildTrack('a'), buildTrack('b')]);
    bloc = LibraryBloc(database: database);
  });

  tearDown(() async {
    await bloc.close();
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  group('LibraryBloc', () {
    test('starts empty', () {
      expect(bloc.state.isEmpty, isTrue);
      expect(bloc.state.favoriteIds, isEmpty);
      expect(bloc.state.playlists, isEmpty);
    });

    test('toggling a favorite updates state and persists it', () async {
      bloc.add(const LibraryFavoriteToggled('fake:a'));
      await until(bloc, (LibraryState s) => s.isFavorite('fake:a'));

      expect(database.isFavorite('fake:a'), isTrue);

      bloc.add(const LibraryFavoriteToggled('fake:a'));
      await until(bloc, (LibraryState s) => !s.isFavorite('fake:a'));

      expect(bloc.state.isFavorite('fake:a'), isFalse);
      expect(database.isFavorite('fake:a'), isFalse);
    });

    test('resolved favorite tracks are exposed for the UI', () async {
      bloc.add(const LibraryFavoriteToggled('fake:b'));
      await until(bloc, (LibraryState s) => s.favoriteTracks.isNotEmpty);

      expect(bloc.state.favoriteTracks.single.id, 'fake:b');
    });

    test('reloads reflect what another writer stored', () async {
      await database.setFavorite('fake:a', true);

      bloc.add(const LibraryFavoritesRequested());
      await until(bloc, (LibraryState s) => s.isFavorite('fake:a'));

      expect(database.isFavorite('fake:a'), isTrue);
    });

    test('creates a playlist flagged for sync', () async {
      bloc.add(const LibraryPlaylistCreated('Road trip'));
      await until(bloc, (LibraryState s) => s.playlists.isNotEmpty);

      final Playlist created = bloc.state.playlists.single;
      expect(created.name, 'Road trip');
      expect(created.trackIds, isEmpty);
      expect(
        created.pendingSync,
        isTrue,
        reason: 'a locally created playlist must be queued for the backend',
      );
    });

    test('adding a track twice does not duplicate it', () async {
      bloc.add(const LibraryPlaylistCreated('Mix'));
      await until(bloc, (LibraryState s) => s.playlists.isNotEmpty);
      final String id = bloc.state.playlists.single.id;

      bloc.add(LibraryPlaylistTrackAdded(playlistId: id, trackId: 'fake:a'));
      await until(
        bloc,
        (LibraryState s) => s.playlists.single.trackIds.isNotEmpty,
      );
      bloc.add(LibraryPlaylistTrackAdded(playlistId: id, trackId: 'fake:a'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.playlists.single.trackIds, <String>['fake:a']);
    });

    test('removing a track from a playlist persists the change', () async {
      bloc.add(const LibraryPlaylistCreated('Mix'));
      await until(bloc, (LibraryState s) => s.playlists.isNotEmpty);
      final String id = bloc.state.playlists.single.id;

      bloc.add(LibraryPlaylistTrackAdded(playlistId: id, trackId: 'fake:a'));
      await until(
        bloc,
        (LibraryState s) => s.playlists.single.trackIds.isNotEmpty,
      );
      bloc.add(LibraryPlaylistTrackAdded(playlistId: id, trackId: 'fake:b'));
      await until(
        bloc,
        (LibraryState s) => s.playlists.single.trackIds.length == 2,
      );

      bloc.add(LibraryPlaylistTrackRemoved(playlistId: id, trackId: 'fake:a'));
      await until(
        bloc,
        (LibraryState s) => s.playlists.single.trackIds.length == 1,
      );

      expect(database.getPlaylist(id)!.trackIds, <String>['fake:b']);
    });

    test('deleting a playlist removes it', () async {
      bloc.add(const LibraryPlaylistCreated('Temp'));
      await until(bloc, (LibraryState s) => s.playlists.isNotEmpty);
      final String id = bloc.state.playlists.single.id;

      bloc.add(LibraryPlaylistDeleted(id));
      await until(bloc, (LibraryState s) => s.playlists.isEmpty);

      expect(bloc.state.playlists, isEmpty);
      expect(database.getPlaylist(id), isNull);
    });

    test('clearing history empties the state', () async {
      await database.recordPlay('fake:a');

      bloc.add(const LibraryFavoritesRequested());
      await until(bloc, (LibraryState s) => s.history.isNotEmpty);
      expect(bloc.state.history, hasLength(1));

      bloc.add(const LibraryHistoryCleared());
      await until(bloc, (LibraryState s) => s.history.isEmpty);

      expect(bloc.state.history, isEmpty);
      expect(database.getHistory(), isEmpty);
    });

    test('historyTracks hydrates ids and skips unknown ones', () async {
      await database.recordPlay('fake:a');
      await database.recordPlay('does-not-exist');
      await database.recordPlay('fake:b');

      bloc.add(const LibraryFavoritesRequested());
      await until(bloc, (LibraryState s) => s.history.isNotEmpty);

      expect(
        bloc.state.historyTracks(database).map((Track t) => t.id),
        <String>['fake:b', 'fake:a'],
        reason: 'history is most-recent-first',
      );
    });
  });
}
