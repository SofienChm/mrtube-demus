part of 'player_bloc.dart';

sealed class PlayerEvent extends Equatable {
  const PlayerEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Start a new listening session from [tracks], beginning at [startIndex].
///
/// Routes by capability: direct-audio tracks go to the background
/// [AudioPlayerHandler]; embed-only tracks go to the in-app embed surface, which
/// cannot play in the background.
final class PlayerTrackRequested extends PlayerEvent {
  const PlayerTrackRequested({required this.tracks, this.startIndex = 0});

  final List<Track> tracks;
  final int startIndex;

  @override
  List<Object?> get props => <Object?>[tracks, startIndex];
}

final class PlayerTogglePlayPause extends PlayerEvent {
  const PlayerTogglePlayPause();
}

final class PlayerNextRequested extends PlayerEvent {
  const PlayerNextRequested();
}

final class PlayerPreviousRequested extends PlayerEvent {
  const PlayerPreviousRequested();
}

final class PlayerSeekRequested extends PlayerEvent {
  const PlayerSeekRequested(this.position);

  final Duration position;

  @override
  List<Object?> get props => <Object?>[position];
}

/// Position ticked forward by the handler's position stream.
///
/// State-only: this must never seek, or each tick would re-seek the player and
/// create a feedback loop.
final class PlayerPositionTicked extends PlayerEvent {
  const PlayerPositionTicked(this.position);

  final Duration position;

  @override
  List<Object?> get props => <Object?>[position];
}

/// Position the user is currently dragging to.
///
/// Held separately from [PlayerPositionTicked] so the incoming stream cannot
/// yank the slider out from under their finger; discarded once the seek
/// completes.
final class PlayerPositionPreviewed extends PlayerEvent {
  const PlayerPositionPreviewed(this.position);

  final Duration position;

  @override
  List<Object?> get props => <Object?>[position];
}

final class PlayerShuffleToggled extends PlayerEvent {
  const PlayerShuffleToggled();
}

final class PlayerRepeatToggled extends PlayerEvent {
  const PlayerRepeatToggled();
}

/// Mirrors a `PlaybackState` broadcast from the audio handler.
final class PlayerPlaybackStateChanged extends PlayerEvent {
  const PlayerPlaybackStateChanged(this.playback);

  final PlaybackState playback;

  @override
  List<Object?> get props => <Object?>[
    playback.processingState,
    playback.playing,
  ];
}

/// Mirrors a `MediaItem` broadcast, used to track the now-playing entry.
final class PlayerMediaItemChanged extends PlayerEvent {
  const PlayerMediaItemChanged(this.item);

  final MediaItem? item;

  @override
  List<Object?> get props => <Object?>[item];
}

/// The embed player reported its own state, for embed-only sources.
final class PlayerEmbedStateChanged extends PlayerEvent {
  const PlayerEmbedStateChanged({
    required this.isPlaying,
    required this.isBuffering,
  });

  final bool isPlaying;
  final bool isBuffering;

  @override
  List<Object?> get props => <Object?>[isPlaying, isBuffering];
}

/// Tracks resolved after the fact and appended to the live queue.
///
/// Queue growth arrives asynchronously, after the originating
/// `PlayerTrackRequested` has already returned, so it is applied through its own
/// event rather than mutating state from a dangling future.
final class PlayerQueueExtended extends PlayerEvent {
  const PlayerQueueExtended(this.appended);

  final List<Track> appended;

  @override
  List<Object?> get props => <Object?>[appended];
}

final class PlayerFailureRaised extends PlayerEvent {
  const PlayerFailureRaised(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

final class PlayerFailureDismissed extends PlayerEvent {
  const PlayerFailureDismissed();
}
