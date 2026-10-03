import 'package:audio_service/audio_service.dart';

import '../models/track.dart';

/// Direct-audio transport, as the player layer consumes it.
///
/// [AudioPlayerHandler] is the production implementation. This seam exists so
/// queue handling can be tested without a real player: the failure worth
/// guarding against is handing `just_audio` a queue whose entries have no
/// stream URL, which silently produces an empty playback sequence.
abstract interface class DirectPlaybackController {
  /// Replaces the queue. Returns false when nothing playable remains.
  Future<bool> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  });

  /// Appends to the live queue and returns the entries the player accepted.
  Future<List<Track>> appendToQueue(List<Track> tracks);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode);

  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode);

  /// Transport state (playing / buffering / processing).
  ///
  /// Replays the current value to new subscribers, so a late listener is not
  /// left with a stale "playing" while the audio is actually paused.
  Stream<PlaybackState> get playbackStateStream;

  /// The item the platform is actually playing, so a skip driven from the lock
  /// screen or notification is reflected in the UI.
  Stream<MediaItem?> get mediaItemStream;

  /// Playhead position. Drives the scrubber for direct-audio tracks.
  ///
  /// Named `positionStream` because `AudioHandler` already defines `position` as
  /// a plain `Duration`; exposing the stream here also keeps consumers off the
  /// `AudioService.position` static.
  Stream<Duration> get positionStream;
}
