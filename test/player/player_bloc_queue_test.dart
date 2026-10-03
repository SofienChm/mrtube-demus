import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/errors/exceptions.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/database_service.dart';
import 'package:mrplay_new/core/services/direct_playback_controller.dart';
import 'package:mrplay_new/core/services/music_source.dart';
import 'package:mrplay_new/core/services/track_repository.dart';
import 'package:mrplay_new/features/player/bloc/player_bloc.dart';

class DirectSource implements MusicSource {
  DirectSource({this.unresolvable = const <String>{}});

  final Set<String> unresolvable;
  int resolveCalls = 0;

  @override
  String get id => 'audius';

  @override
  bool get supportsDirectAudio => true;

  @override
  bool get searchIsQuotaBound => false;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) => throw UnimplementedError();

  @override
  Future<Track> resolve(Track track) async {
    resolveCalls++;
    if (unresolvable.contains(track.sourceId)) {
      throw const ContentUnavailableException('gone');
    }
    return track.copyWith(
      streamUrl: 'https://cdn.example/${track.sourceId}.mp3',
    );
  }

  @override
  void dispose() {}
}

/// Records what the bloc asked the player to do.
class FakeAudioController implements DirectPlaybackController {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<PlaybackState> _playback =
      StreamController<PlaybackState>.broadcast();
  final StreamController<MediaItem?> _mediaItem =
      StreamController<MediaItem?>.broadcast();
  final List<List<Track>> loadCalls = <List<Track>>[];
  final List<List<Track>> appendCalls = <List<Track>>[];

  int playCalls = 0;
  int pauseCalls = 0;
  bool loadSucceeds = true;
  int loadInitialIndex = -1;

  /// Mirrors the real handler's contract: entries with no URL cannot be played,
  /// so it drops them and reports what survived.
  @override
  Future<bool> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    if (!loadSucceeds) return false;
    final List<Track> playable = tracks
        .where((Track t) => t.streamUrl != null)
        .toList(growable: false);
    if (playable.isEmpty) return false;
    loadCalls.add(playable);
    loadInitialIndex = initialIndex;
    return true;
  }

  @override
  Future<List<Track>> appendToQueue(List<Track> tracks) async {
    final List<Track> playable = tracks
        .where((Track t) => t.streamUrl != null)
        .toList(growable: false);
    appendCalls.add(playable);
    return playable;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _broadcastState(playing: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _broadcastState(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<PlaybackState> get playbackStateStream => _playback.stream;

  @override
  Stream<MediaItem?> get mediaItemStream => _mediaItem.stream;

  /// Mirrors the real handler: the player pushes transport state rather than the
  /// caller assuming the outcome.
  void _broadcastState({required bool playing}) {
    _playback.add(
      PlaybackState(
        controls: <MediaControl>[
          if (playing) MediaControl.pause else MediaControl.play,
        ],
        playing: playing,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  /// Simulates a skip driven from the lock screen or notification.
  void emitMediaItem(MediaItem? item) => _mediaItem.add(item);

  Future<void> dispose() async {
    await _position.close();
    await _playback.close();
    await _mediaItem.close();
  }
}

class FakeEmbedController implements EmbedPlaybackController {
  final StreamController<EmbedPlaybackSnapshot> _changes =
      StreamController<EmbedPlaybackSnapshot>.broadcast();
  final List<Track> played = <Track>[];
  bool playSucceeds = true;

  @override
  Future<bool> play(Track track) async {
    played.add(track);
    return playSucceeds;
  }

  @override
  Future<bool> togglePlay() async => false;

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async => _changes.close();

  @override
  Stream<EmbedPlaybackSnapshot> get changes => _changes.stream;
}

Track direct(String id) => Track(
  id: 'audius:$id',
  title: 'Title $id',
  artist: 'Artist $id',
  sourceId: id,
  thumbnailUrl: null,
  duration: const Duration(minutes: 3),
);

Track embed(String id) => Track(
  id: 'youtube:$id',
  title: 'Title $id',
  artist: 'Artist $id',
  sourceId: id,
  thumbnailUrl: null,
  playbackCapability: PlaybackCapability.embedOnly,
);

/// Polls until [condition] holds. Queue growth is fire-and-forget by design, so
/// there is no event to await.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory storeDir;
  late DatabaseService database;
  late FakeAudioController audio;
  late FakeEmbedController embedController;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('mrplay_player_test');
    database = await DatabaseService.initAt(storeDir.path);
    audio = FakeAudioController();
    embedController = FakeEmbedController();
  });

  tearDown(() async {
    await audio.dispose();
    await embedController.dispose();
    await database.close();
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  PlayerBloc buildBloc(TrackRepository repository) => PlayerBloc(
    repository: repository,
    audioHandler: audio,
    embedController: embedController,
  );

  TrackRepository repoFor(List<MusicSource> sources) =>
      TrackRepository(database: database, sources: sources);

  group('PlayerBloc queue resolution', () {
    test('hands the player a queue with no unresolved entries', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[for (int i = 0; i < 20; i++) direct('t$i')],
          startIndex: 0,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      expect(audio.loadCalls, hasLength(1));
      for (final Track t in audio.loadCalls.single) {
        expect(
          t.streamUrl,
          isNotNull,
          reason: 'an unresolved entry here is the original bug',
        );
      }
      expect(bloc.state.current!.sourceId, 't0');
    });

    test('starts the requested track, not the first resolved one', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[for (int i = 0; i < 20; i++) direct('t$i')],
          startIndex: 7,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      expect(
        bloc.state.current!.sourceId,
        't7',
        reason: 'a wrong start index is an audible off-by-one',
      );
      expect(bloc.state.index, audio.loadInitialIndex);
    });

    test('drops dead entries and still starts the requested track', () async {
      final TrackRepository repository = repoFor(<MusicSource>[
        DirectSource(unresolvable: <String>{'t1', 't2'}),
      ]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[for (int i = 0; i < 20; i++) direct('t$i')],
          startIndex: 5,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      expect(bloc.state.current!.sourceId, 't5');
      expect(
        audio.loadCalls.single.map((Track t) => t.sourceId),
        isNot(contains('t1')),
      );
    });

    test('grows the queue past the initial window so next keeps working', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[for (int i = 0; i < 40; i++) direct('t$i')],
          startIndex: 0,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );
      await waitUntil(() => bloc.state.queue.length >= 40);

      final List<String> queued = bloc.state.queue
          .map((Track t) => t.sourceId)
          .toList();

      // Initial window is small; growth must reach the end without duplicates.
      expect(
        queued.length,
        greaterThan(audio.loadCalls.single.length),
        reason: 'the rest of the list must be appended',
      );
      expect(queued, hasLength(40));
      expect(queued.toSet(), hasLength(queued.length), reason: 'no duplicates');
      expect(queued, <String>[
        for (int i = 0; i < queued.length; i++) 't$i',
      ], reason: 'growth must stay in order');
    });

    test('growth does not duplicate queued tracks when entries are dropped', () async {
      // t1 and t2 fail to resolve, so the initial queue is shorter than the
      // window that was requested. Growth must still resume at the right place.
      final TrackRepository repository = repoFor(<MusicSource>[
        DirectSource(unresolvable: <String>{'t1', 't2'}),
      ]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[for (int i = 0; i < 40; i++) direct('t$i')],
          startIndex: 0,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      // 40 tracks, 2 dead: growth is done once the whole rest has landed.
      await waitUntil(() => bloc.state.queue.length >= 38);

      final List<String> queued = bloc.state.queue
          .map((Track t) => t.sourceId)
          .toList();

      // Every track except the two that cannot be resolved, in order.
      final List<String> want = <String>[
        for (int i = 0; i < 40; i++)
          if (i != 1 && i != 2) 't$i',
      ];

      expect(queued, hasLength(38));
      expect(
        queued.toSet(),
        hasLength(queued.length),
        reason: 'a dropped entry must not shift growth backwards',
      );
      expect(queued, want, reason: 'order preserved, dead entries omitted');
    });

    test('falls back to the embed player for an embed-only track', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(tracks: <Track>[embed('v0')], startIndex: 0),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      expect(embedController.played.single.sourceId, 'v0');
      expect(
        audio.loadCalls,
        isEmpty,
        reason: 'embed-only tracks have no URL for just_audio',
      );
    });

    test('surfaces an error when the player refuses to start', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);
      audio.loadSucceeds = false;

      bloc.add(
        PlayerTrackRequested(tracks: <Track>[direct('t0')], startIndex: 0),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.error,
      );

      expect(bloc.state.failure, isNotNull);
    });

    test('a new request supersedes an in-flight queue growth', () async {
      final DirectSource source = DirectSource();
      final TrackRepository repository = repoFor(<MusicSource>[source]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[for (int i = 0; i < 60; i++) direct('t$i')],
          startIndex: 0,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      // Switch to a different, short queue while growth is still resolving.
      bloc.add(
        PlayerTrackRequested(tracks: <Track>[direct('other')], startIndex: 0),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) =>
            s.status == PlayerStatus.ready && s.current?.sourceId == 'other',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.queue.map((Track t) => t.sourceId), <String>[
        'other',
      ], reason: 'stale growth must not repopulate a replaced queue');
    });

    test('pause flips the transport state and play resumes it', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(tracks: <Track>[direct('t0')], startIndex: 0),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );
      expect(bloc.state.isPlaying, isTrue);

      bloc.add(const PlayerTogglePlayPause());
      await waitUntil(() => !bloc.state.isPlaying);
      expect(audio.pauseCalls, 1);

      // The reported bug: with isPlaying stuck on true, this second tap called
      // pause() again and playback could never resume without a track change.
      bloc.add(const PlayerTogglePlayPause());
      await waitUntil(() => bloc.state.isPlaying);
      expect(audio.playCalls, 1);
    });

    test('a track started without an optimistic flag still reports playing', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      // A player that pushes state before the bloc ever optimistically sets it.
      bloc.add(
        PlayerTrackRequested(tracks: <Track>[direct('t0')], startIndex: 0),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      bloc.add(const PlayerTogglePlayPause());
      await waitUntil(() => !bloc.state.isPlaying);
      expect(bloc.state.isPlaying, isFalse);
    });

    test('a skip from the notification updates the current track', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(
        PlayerTrackRequested(
          tracks: <Track>[direct('t0'), direct('t1')],
          startIndex: 0,
        ),
      );
      await bloc.stream.firstWhere(
        (PlayerState s) => s.status == PlayerStatus.ready,
      );

      audio.emitMediaItem(
        MediaItem(id: 'audius:t1', title: 'Title t1', artist: 'Artist t1'),
      );
      await waitUntil(() => bloc.state.current?.sourceId == 't1');

      expect(bloc.state.current!.sourceId, 't1');
    });

    test('ignores an empty request', () async {
      final TrackRepository repository = repoFor(<MusicSource>[DirectSource()]);
      final PlayerBloc bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(const PlayerTrackRequested(tracks: <Track>[], startIndex: 0));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(audio.loadCalls, isEmpty);
    });
  });
}
