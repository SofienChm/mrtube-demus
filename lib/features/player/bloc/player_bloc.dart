import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/failures.dart';
import '../../../core/models/track.dart';
import '../../../core/services/direct_playback_controller.dart';
import '../../../core/services/track_repository.dart';

part 'player_event.dart';
part 'player_state.dart';

/// Owns playback intent for the whole app.
///
/// Two transport paths coexist here, which is the central design problem of this
/// app:
///
/// * **Direct audio** ([PlaybackCapability.directAudio]) is driven by
///   [AudioPlayerHandler] / `just_audio`. Full support: background playback,
///   lock-screen transport, seeking, prefetch.
/// * **Embed-only** ([PlaybackCapability.embedOnly], e.g. YouTube's official
///   player) plays inside the app. Works while foregrounded; stops on
///   background and offers no lock-screen controls.
///
/// This bloc normalises both into a single [PlayerState] so the mini-player and
/// the full-screen sheet never need to care which path is active.
final class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  PlayerBloc({
    required this.repository,
    required this.audioHandler,
    required this.embedController,
  }) : super(const PlayerState()) {
    on<PlayerTrackRequested>(_onTrackRequested, transformer: _sequential());
    on<PlayerTogglePlayPause>(_onTogglePlayPause);
    on<PlayerNextRequested>(_onNext, transformer: _sequential());
    on<PlayerPreviousRequested>(_onPrevious, transformer: _sequential());
    on<PlayerSeekRequested>(_onSeek);
    on<PlayerPositionTicked>(_onPositionTicked);
    on<PlayerPositionPreviewed>(_onPositionPreviewed);
    on<PlayerShuffleToggled>(_onShuffleToggled);
    on<PlayerRepeatToggled>(_onRepeatToggled);
    on<PlayerPlaybackStateChanged>(_onPlaybackStateChanged);
    on<PlayerMediaItemChanged>(_onMediaItemChanged);
    on<PlayerEmbedStateChanged>(_onEmbedStateChanged);
    on<PlayerQueueExtended>(_onQueueExtended);
    on<PlayerFailureRaised>(_onFailureRaised);
    on<PlayerFailureDismissed>(_onFailureDismissed);

    _positionSubscription = audioHandler.positionStream.listen((
      Duration position,
    ) {
      if (!isClosed) add(PlayerPositionTicked(position));
    });

    // Transport state is pushed from the player, never assumed. Without this the
    // bloc would keep whatever `isPlaying` it set optimistically when it started
    // a track, so pause would leave the UI on "playing" and the next tap would
    // call pause() again on an already-paused player.
    _playbackSubscription = audioHandler.playbackStateStream.listen((
      PlaybackState playback,
    ) {
      if (!isClosed) add(PlayerPlaybackStateChanged(playback));
    });

    // Keeps the UI honest about what the platform is actually playing, so a skip
    // from the lock screen or notification updates the mini-player too.
    _mediaItemSubscription = audioHandler.mediaItemStream.listen((
      MediaItem? item,
    ) {
      if (!isClosed) add(PlayerMediaItemChanged(item));
    });

    // Embed-only tracks bypass AudioService entirely, so their transport state
    // and scrub position arrive on their own stream.
    _embedSubscription = embedController.changes.listen((
      EmbedPlaybackSnapshot snapshot,
    ) {
      if (isClosed) return;
      add(
        PlayerEmbedStateChanged(
          isPlaying: snapshot.isPlaying,
          isBuffering: snapshot.isBuffering,
        ),
      );
      add(PlayerPositionTicked(snapshot.position));
    });
  }

  final TrackRepository repository;
  final DirectPlaybackController audioHandler;
  final EmbedPlaybackController embedController;

  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<PlaybackState> _playbackSubscription;
  late final StreamSubscription<MediaItem?> _mediaItemSubscription;
  late final StreamSubscription<EmbedPlaybackSnapshot> _embedSubscription;

  /// Tracks how many entries past the initial window have been requested, so a
  /// growing queue cannot redeliver the same tracks twice.
  static const int _queueGrowthBatch = 10;

  /// Monotonic token for the in-flight queue growth pass. Bumped on every new
  /// request so a slow resolution cannot append to a queue the user replaced.
  int _queueGrowthGeneration = 0;

  /// Serialises transport commands so a rapid next/next/next cannot interleave
  /// three queue swaps.
  static EventTransformer<E> _sequential<E>() =>
      (Stream<E> events, EventMapper<E> mapper) => events.asyncExpand(mapper);

  Future<void> _onTrackRequested(
    PlayerTrackRequested event,
    Emitter<PlayerState> emit,
  ) async {
    if (event.tracks.isEmpty) return;

    // Invalidate any queue growth still in flight from the previous session.
    _queueGrowthGeneration++;

    final int requestedIndex = event.startIndex.clamp(
      0,
      event.tracks.length - 1,
    );
    final Track requested = event.tracks[requestedIndex];

    emit(
      state.copyWith(
        status: PlayerStatus.loading,
        queue: event.tracks,
        index: requestedIndex,
        current: requested,
        position: Duration.zero,
        clearScrubPosition: true,
        duration: requested.duration,
        clearFailure: true,
      ),
    );

    // Ask for a queue that is already playable rather than handing raw search
    // results to the player. Unresolved tracks carry no `streamUrl`, so the
    // handler filters them out and can end up with an empty queue.
    //
    // A null result means the requested track cannot play as direct audio, which
    // makes this an embed-only session.
    final ({List<Track> queue, int startIndex, int nextSourceIndex})? resolved =
        await repository.resolveQueue(event.tracks, requestedIndex);

    if (resolved == null) {
      final bool started = await embedController.play(requested);
      emit(
        state.copyWith(
          status: started ? PlayerStatus.ready : PlayerStatus.error,
          current: requested,
          isPlaying: started,
          failure: started ? null : const UnavailableContentFailure(),
        ),
      );
      return;
    }

    final List<Track> queue = resolved.queue;
    final int startIndex = resolved.startIndex;

    final bool loaded = await audioHandler.loadQueue(
      queue,
      initialIndex: startIndex,
    );
    if (!loaded) {
      emit(
        state.copyWith(
          status: PlayerStatus.error,
          failure: const PlaybackFailure('Could not start playback.'),
        ),
      );
      return;
    }

    // From here the queue is the resolved one, so `_adjacentIndex` and the
    // player's own indices refer to the same positions.
    emit(
      state.copyWith(
        status: PlayerStatus.ready,
        queue: queue,
        index: startIndex,
        current: queue[startIndex],
        isPlaying: true,
      ),
    );

    unawaited(_growQueue(event.tracks, resolved.nextSourceIndex));
  }

  /// Appends the rest of the list to the live queue as it resolves.
  ///
  /// Runs in batches so "next" keeps working past the initial window instead of
  /// dead-ending. Cancelled when a newer request supersedes it, otherwise a slow
  /// resolution would append tracks to a queue the user has already replaced.
  Future<void> _growQueue(List<Track> all, int nextOffset) async {
    if (nextOffset >= all.length) return;

    final int generation = ++_queueGrowthGeneration;

    for (int from = nextOffset; from < all.length; from += _queueGrowthBatch) {
      if (isClosed || generation != _queueGrowthGeneration) return;

      final List<Track> batch = await repository.resolveRange(
        all,
        from,
        limit: _queueGrowthBatch,
      );
      if (isClosed || batch.isEmpty) continue;

      final List<Track> appended = await audioHandler.appendToQueue(batch);
      if (isClosed || appended.isEmpty) continue;
      if (generation != _queueGrowthGeneration) return;

      add(PlayerQueueExtended(appended));
    }
  }

  void _onQueueExtended(PlayerQueueExtended event, Emitter<PlayerState> emit) {
    if (event.appended.isEmpty) return;
    emit(state.copyWith(queue: <Track>[...state.queue, ...event.appended]));
  }

  Future<void> _onTogglePlayPause(
    PlayerTogglePlayPause event,
    Emitter<PlayerState> emit,
  ) async {
    if (!state.hasTrack) return;

    if (state.isEmbedOnly) {
      final bool next = await embedController.togglePlay();
      emit(state.copyWith(isPlaying: next));
      return;
    }
    if (state.isPlaying) {
      await audioHandler.pause();
    } else {
      await audioHandler.play();
    }
  }

  Future<void> _onNext(
    PlayerNextRequested event,
    Emitter<PlayerState> emit,
  ) async {
    final int? next = _adjacentIndex(1);
    if (next == null) return;
    add(PlayerTrackRequested(tracks: state.queue, startIndex: next));
  }

  Future<void> _onPrevious(
    PlayerPreviousRequested event,
    Emitter<PlayerState> emit,
  ) async {
    // Standard behaviour: restart the track first, then step back.
    if (state.position > const Duration(seconds: 3)) {
      add(const PlayerSeekRequested(Duration.zero));
      return;
    }
    final int? previous = _adjacentIndex(-1);
    if (previous == null) return;
    add(PlayerTrackRequested(tracks: state.queue, startIndex: previous));
  }

  /// Next/previous index honouring shuffle and repeat, or null when there is
  /// nowhere to go.
  int? _adjacentIndex(int delta) {
    if (state.queue.length < 2) return null;

    if (state.isShuffleOn && state.queue.length > 1) {
      // Deterministic-enough shuffle: step forward but skip the current index.
      final int span = state.queue.length - 1;
      final int step = 1 + (state.index.abs() % span);
      return (state.index + delta * step) % state.queue.length;
    }

    final int next = state.index + delta;
    if (next < 0) {
      return state.repeatMode == AudioServiceRepeatMode.all
          ? state.queue.length - 1
          : 0;
    }
    if (next >= state.queue.length) {
      return state.repeatMode == AudioServiceRepeatMode.all ? 0 : null;
    }
    return next;
  }

  Future<void> _onSeek(
    PlayerSeekRequested event,
    Emitter<PlayerState> emit,
  ) async {
    // A completed seek ends the scrub, so release the preview and let the
    // stream resume driving the bar.
    emit(state.copyWith(position: event.position, clearScrubPosition: true));
    if (state.isEmbedOnly) {
      await embedController.seek(event.position);
      return;
    }
    await audioHandler.seek(event.position);
  }

  void _onPositionPreviewed(
    PlayerPositionPreviewed event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(scrubPosition: event.position));
  }

  Future<void> _onShuffleToggled(
    PlayerShuffleToggled event,
    Emitter<PlayerState> emit,
  ) async {
    final bool next = !state.isShuffleOn;
    emit(state.copyWith(isShuffleOn: next));
    await audioHandler.setShuffleMode(
      next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  Future<void> _onRepeatToggled(
    PlayerRepeatToggled event,
    Emitter<PlayerState> emit,
  ) async {
    // off -> one -> all -> off
    final AudioServiceRepeatMode next = switch (state.repeatMode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.all,
      _ => AudioServiceRepeatMode.none,
    };
    emit(state.copyWith(repeatMode: next));
    await audioHandler.setRepeatMode(next);
  }

  void _onPlaybackStateChanged(
    PlayerPlaybackStateChanged event,
    Emitter<PlayerState> emit,
  ) {
    final PlaybackState playback = event.playback;
    emit(
      state.copyWith(
        status: switch (playback.processingState) {
          AudioProcessingState.idle => PlayerStatus.idle,
          AudioProcessingState.loading => PlayerStatus.loading,
          AudioProcessingState.buffering => PlayerStatus.buffering,
          AudioProcessingState.ready => PlayerStatus.ready,
          AudioProcessingState.completed => PlayerStatus.completed,
          AudioProcessingState.error => PlayerStatus.error,
        },
        isPlaying: playback.playing,
      ),
    );
  }

  void _onMediaItemChanged(
    PlayerMediaItemChanged event,
    Emitter<PlayerState> emit,
  ) {
    final MediaItem? item = event.item;
    if (item == null) return;

    // Keep `current` in sync with what the platform is actually playing, so a
    // skip driven from the lock screen reflects here without a round trip.
    final Track? resolved = repository.database.getTrack(item.id);
    if (resolved != null && resolved.id != state.current?.id) {
      emit(
        state.copyWith(
          current: resolved,
          duration: item.duration ?? resolved.duration,
          position: Duration.zero,
        ),
      );
    } else if (item.duration != null && item.duration != state.duration) {
      emit(state.copyWith(duration: item.duration));
    }
  }

  void _onEmbedStateChanged(
    PlayerEmbedStateChanged event,
    Emitter<PlayerState> emit,
  ) {
    emit(
      state.copyWith(
        status: event.isBuffering ? PlayerStatus.buffering : PlayerStatus.ready,
        isPlaying: event.isPlaying,
      ),
    );
  }

  void _onFailureRaised(PlayerFailureRaised event, Emitter<PlayerState> emit) {
    emit(state.copyWith(status: PlayerStatus.error, failure: event.failure));
  }

  void _onFailureDismissed(
    PlayerFailureDismissed event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(clearFailure: true));
  }

  /// Records the tick in state without touching the transport.
  void _onPositionTicked(
    PlayerPositionTicked event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(position: event.position));
  }

  @override
  Future<void> close() async {
    await _positionSubscription.cancel();
    await _playbackSubscription.cancel();
    await _mediaItemSubscription.cancel();
    await _embedSubscription.cancel();
    _queueGrowthGeneration++;
    await embedController.dispose();
    return super.close();
  }
}

/// Thin wrapper around the official YouTube IFrame Player API.
///
/// Kept as an interface so [PlayerBloc] does not depend on a webview package,
/// which keeps the bloc testable without platform channels.
abstract interface class EmbedPlaybackController {
  /// Plays [track] in the embed surface. Returns false when it cannot start.
  Future<bool> play(Track track);

  /// Returns the new playing state.
  Future<bool> togglePlay();

  Future<void> seek(Duration position);

  Future<void> dispose();

  /// Transport changes reported by the embed surface.
  ///
  /// The official player is not wired into `AudioService.position`, so without
  /// this the scrubber would be frozen for embed-only tracks.
  Stream<EmbedPlaybackSnapshot> get changes;
}

/// Immutable view of the embed player's state at a point in time.
final class EmbedPlaybackSnapshot {
  const EmbedPlaybackSnapshot({
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
}
