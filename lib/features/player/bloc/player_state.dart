part of 'player_bloc.dart';

enum PlayerStatus { idle, loading, ready, buffering, completed, error }

final class PlayerState extends Equatable {
  const PlayerState({
    this.status = PlayerStatus.idle,
    this.current,
    this.queue = const <Track>[],
    this.index = 0,
    this.isPlaying = false,
    this.isShuffleOn = false,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.position = Duration.zero,
    this.scrubPosition,
    this.duration,
    this.failure,
  });

  final PlayerStatus status;

  /// Now-playing track. Null only before the first request.
  final Track? current;

  /// The session queue, including any embed-only entries.
  final List<Track> queue;

  final int index;
  final bool isPlaying;
  final bool isShuffleOn;
  final AudioServiceRepeatMode repeatMode;

  /// Last known position. Refreshed from the handler's position stream rather
  /// than stored per-frame in state.
  final Duration position;

  /// Where the user is dragging to, or null when not scrubbing.
  ///
  /// Precedence over [position] matters: the incoming stream keeps ticking while
  /// a drag is in progress and would otherwise snap the slider back.
  final Duration? scrubPosition;

  final Duration? duration;
  final Failure? failure;

  /// Position to render, preferring an in-progress scrub.
  Duration get displayPosition => scrubPosition ?? position;

  /// True when the current track cannot play with background audio support.
  /// The UI uses this to warn before the user backgrounds the app.
  bool get isEmbedOnly =>
      current?.playbackCapability == PlaybackCapability.embedOnly;

  bool get hasTrack => current != null;

  /// Position as a 0..1 fraction, guarding against a zero or unknown duration.
  double get progress {
    final Duration? total = duration;
    if (total == null || total.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  PlayerState copyWith({
    PlayerStatus? status,
    Track? current,
    List<Track>? queue,
    int? index,
    bool? isPlaying,
    bool? isShuffleOn,
    AudioServiceRepeatMode? repeatMode,
    Duration? position,
    Duration? scrubPosition,
    Duration? duration,
    Failure? failure,
    bool clearFailure = false,
    bool clearScrubPosition = false,
  }) {
    return PlayerState(
      status: status ?? this.status,
      current: current ?? this.current,
      queue: queue ?? this.queue,
      index: index ?? this.index,
      isPlaying: isPlaying ?? this.isPlaying,
      isShuffleOn: isShuffleOn ?? this.isShuffleOn,
      repeatMode: repeatMode ?? this.repeatMode,
      position: position ?? this.position,
      scrubPosition: clearScrubPosition
          ? null
          : (scrubPosition ?? this.scrubPosition),
      duration: duration ?? this.duration,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    current,
    queue,
    index,
    isPlaying,
    isShuffleOn,
    repeatMode,
    position,
    scrubPosition,
    duration,
    failure,
  ];
}
