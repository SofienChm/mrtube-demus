import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'direct_playback_controller.dart';

/// Bridges `just_audio` to the platform's media controls.
///
/// Owns the single [AudioPlayer] instance and translates its state model into
/// [PlaybackState] broadcasts that the notification, lock screen, CarPlay,
/// Android Auto, and the Flutter UI all listen to.
///
/// Only [PlaybackCapability.directAudio] tracks can flow through here — the
/// player requires a real URL. Embed-only providers are routed by `PlayerBloc`
/// to a separate embed surface instead.
final class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements DirectPlaybackController {
  AudioPlayerHandler({required this.hooks}) {
    // just_audio does not configure an audio session for you. Without this the
    // app ignores audio focus, so it talks over other apps and misbehaves when a
    // headset is unplugged or a call interrupts it.
    unawaited(_configureAudioSession());

    _player = AudioPlayer(
      // Pause automatically on a phone call, resume when the OS allows it.
      handleInterruptions: true,
      // Tolerate a few dead tracks in a row rather than halting the whole queue.
      maxSkipsOnError: 3,
    );
    _attachListeners();
  }

  Future<void> _configureAudioSession() async {
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.music());
    } on Object {
      // Non-fatal. Playback still works; focus routing just falls back to the
      // platform default rather than failing app startup.
    }
  }

  /// Narrow callback surface the handler needs from the persistence layer.
  ///
  /// Injected rather than importing `DatabaseService` directly so the handler
  /// stays unit-testable and free of a Hive dependency.
  final DatabaseServiceHooks hooks;

  late final AudioPlayer _player;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  /// Guards against re-entrant `load()` calls when just_audio fires state
  /// changes synchronously during a source swap.
  bool _isSwapping = false;

  AudioPlayer get player => _player;

  MediaItem? _itemAt(int index) {
    final List<MediaItem> items = queue.value;
    if (index < 0 || index >= items.length) return null;
    return items[index];
  }

  // -------------------------------------------------------------- lifecycle

  /// Loads a queue of directly-playable tracks and begins at [initialIndex].
  ///
  /// Returns false when [tracks] contains no directly-playable entry, letting
  /// the caller fall back to embed playback rather than failing silently.
  @override
  Future<bool> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    final List<Track> playable = <Track>[
      for (final Track t in tracks)
        if (t.isDirectAudio && t.streamUrl != null) t,
    ];
    if (playable.isEmpty) return false;

    _isSwapping = true;
    try {
      final List<int> indexMap = <int>[
        for (int i = 0; i < tracks.length; i++)
          if (tracks[i].isDirectAudio && tracks[i].streamUrl != null) i,
      ];
      final int target = indexMap
          .indexOf(initialIndex)
          .clamp(0, indexMap.length - 1);

      // `preload: false` (formerly `useLazyPreparation`) loads each source just
      // before it is needed, keeping memory flat on long queues.
      await _player.setAudioSources(
        <AudioSource>[
          for (final Track t in playable)
            AudioSource.uri(Uri.parse(t.streamUrl!), tag: t.id),
        ],
        initialIndex: target,
        initialPosition: Duration.zero,
        preload: false,
      );

      queue.add(<MediaItem>[for (final Track t in playable) _toMediaItem(t)]);

      if (autoPlay) unawaited(_player.play());
      return true;
    } on PlayerException {
      return false;
    } on PlayerInterruptedException {
      return false;
    } finally {
      _isSwapping = false;
    }
  }

  /// Loads a single track into a fresh queue.
  Future<bool> loadTrack(Track track, {bool autoPlay = true}) =>
      loadQueue(<Track>[track], initialIndex: 0, autoPlay: autoPlay);

  /// Appends resolved tracks to the end of the live queue.
  ///
  /// Playback start latency is the most sensitive metric in a music player, so
  /// [loadQueue] is handed only the window that is needed to start playing.
  /// This grows the queue as the rest of the list resolves, which is what keeps
  /// "next" working past that window instead of dead-ending.
  ///
  /// Returns the tracks actually appended so the caller can keep its own queue
  /// view in sync — a non-empty return of fewer entries than passed in means
  /// some could not be resolved.
  @override
  Future<List<Track>> appendToQueue(List<Track> tracks) async {
    final List<Track> playable = <Track>[
      for (final Track t in tracks)
        if (t.isDirectAudio && t.streamUrl != null) t,
    ];
    if (playable.isEmpty) return const <Track>[];

    _isSwapping = true;
    try {
      await _player.addAudioSources(<AudioSource>[
        for (final Track t in playable)
          AudioSource.uri(Uri.parse(t.streamUrl!), tag: t.id),
      ]);
      queue.add(<MediaItem>[
        ...queue.value,
        for (final Track t in playable) _toMediaItem(t),
      ]);
      return playable;
    } on PlayerException {
      return const <Track>[];
    } on PlayerInterruptedException {
      return const <Track>[];
    } finally {
      _isSwapping = false;
    }
  }

  // ------------------------------------------------------------- listeners

  void _attachListeners() {
    // Position is intentionally NOT broadcast on every tick. `audio_service`
    // projects position from `updatePosition` plus elapsed time, so emitting
    // ~200 events/second would only burn frames. The UI reads the dedicated
    // `AudioService.position` stream for the scrubber instead.
    _subscriptions.add(
      _player.playerStateStream.listen(
        (PlayerState state) => _broadcast(state),
        onError: (Object error) => _broadcastError(error),
      ),
    );

    _subscriptions.add(
      _player.durationStream.listen((Duration? duration) {
        // Feed the true duration back onto the MediaItem so the lock screen and
        // notification show an accurate scrubber instead of the metadata guess.
        final MediaItem? item = mediaItem.value;
        if (item != null && duration != null && item.duration != duration) {
          mediaItem.add(item.copyWith(duration: duration));
        }
      }),
    );

    _subscriptions.add(
      _player.currentIndexStream.listen((int? index) {
        if (index == null || _isSwapping) return;
        final MediaItem? item = _itemAt(index);
        if (item == null) return;
        mediaItem.add(item);
        unawaited(hooks.onTrackStarted(item.id));
      }),
    );

    // just_audio 0.10 moved errors off `playbackEventStream` onto its own sink.
    _subscriptions.add(
      _player.errorStream.listen((PlayerException error) {
        _broadcastError(error);
      }),
    );

    _subscriptions.add(
      _player.sequenceStateStream.listen((SequenceState? state) {
        if (state == null) return;
        _broadcast(_player.playerState, queueIndex: _player.currentIndex);
      }),
    );
  }

  // -------------------------------------------------------------- broadcast

  void _broadcast(PlayerState state, {int? queueIndex}) {
    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (state.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const <int>[0, 1, 3],
        processingState: _mapProcessing(state.processingState),
        playing: state.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueIndex ?? _player.currentIndex,
      ),
    );
  }

  static AudioProcessingState _mapProcessing(ProcessingState state) =>
      switch (state) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

  void _broadcastError(Object error) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        errorMessage: '$error',
      ),
    );
  }

  // ----------------------------------------------------- handler callbacks

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

  @override
  Stream<MediaItem?> get mediaItemStream => mediaItem;

  @override
  Stream<Duration> get positionStream => AudioService.position;

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    // Standard behaviour: restart the track unless we are near its start.
    final Duration position = _player.position;
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.none ||
      AudioServiceRepeatMode.group => LoopMode.off,
    });
    await super.setRepeatMode(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode != AudioServiceShuffleMode.none,
    );
    await super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final List<MediaItem> next = <MediaItem>[...queue.value, mediaItem];
    await _insertIntoPlayer(next.length - 1, mediaItem);
    queue.add(next);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    final List<MediaItem> next = <MediaItem>[...queue.value];
    next.insert(index.clamp(0, next.length), mediaItem);
    await _insertIntoPlayer(index.clamp(0, next.length - 1), mediaItem);
    queue.add(next);
  }

  /// Mirrors an audio_service queue edit into the just_audio playlist.
  Future<void> _insertIntoPlayer(int index, MediaItem item) async {
    final Track? track = await hooks.resolveTrack(item.id);
    if (track == null || !track.isDirectAudio) {
      throw UnavailableContentException('Track ${item.id} is not streamable.');
    }
    final String? url = track.streamUrl;
    if (url == null) {
      throw UnavailableContentException(
        'Track ${item.id} has no resolved URL.',
      );
    }
    await _player.insertAudioSource(
      index,
      AudioSource.uri(Uri.parse(url), tag: item.id),
    );
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final int index = queue.value.indexOf(mediaItem);
    if (index < 0) return;
    await _player.removeAudioSourceAt(index);
    final List<MediaItem> next = <MediaItem>[...queue.value]..removeAt(index);
    queue.add(next);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final int index = queue.value.indexWhere((MediaItem i) => i.id == mediaId);
    if (index < 0) return;
    await skipToQueueItem(index);
  }

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    artUri: track.thumbnailUrl == null ? null : Uri.parse(track.thumbnailUrl!),
    extras: <String, dynamic>{'playback': track.playbackCapability.name},
  );

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'setSpeed':
        final Object? raw = extras?['speed'];
        if (raw is num) await _player.setSpeed(raw.toDouble());
        return null;
      default:
        return super.customAction(name, extras);
    }
  }

  /// Tears down listeners and the platform player.
  ///
  /// Deliberately not an override: `BaseAudioHandler` exposes no `dispose`, so
  /// this is called explicitly during app teardown.
  Future<void> release() async {
    for (final StreamSubscription<Object?> sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _player.dispose();
  }
}

/// Persistence callbacks the audio handler needs, kept as an interface so this
/// class has no direct dependency on Hive.
abstract interface class DatabaseServiceHooks {
  /// Fired when a new track becomes current, for history bookkeeping.
  Future<void> onTrackStarted(String trackId);

  /// Loads a track by id so queue edits can resolve a playable URL.
  Future<Track?> resolveTrack(String trackId);
}

/// Thrown when an operation targets a track the current source cannot play.
final class UnavailableContentException implements Exception {
  const UnavailableContentException(this.message);

  final String message;

  @override
  String toString() => 'UnavailableContentException: $message';
}
