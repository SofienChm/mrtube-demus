import 'dart:async';

import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/models/track.dart';
import '../bloc/player_bloc.dart'
    show EmbedPlaybackController, EmbedPlaybackSnapshot;

/// Plays embed-only sources (currently YouTube) through the official IFrame
/// Player API.
///
/// Important limitation, surfaced by `PlayerState.isEmbedOnly`: an embedded web
/// player is suspended when the app is backgrounded and publishes no lock-screen
/// metadata, so background audio is unavailable for these tracks. That is a
/// property of the official player rather than a gap in this wiring, and it is
/// the reason direct-audio sources exist in the app at all.
final class YoutubeEmbedController implements EmbedPlaybackController {
  final YoutubePlayerController _controller = YoutubePlayerController();
  final StreamController<EmbedPlaybackSnapshot> _changes =
      StreamController<EmbedPlaybackSnapshot>.broadcast();

  StreamSubscription<YoutubePlayerValue>? _valueSubscription;
  Timer? _positionTimer;
  bool _loaded = false;
  Duration _position = Duration.zero;

  /// Widget to mount in the full-screen player when the current track is
  /// embed-only.
  YoutubePlayerController get controller => _controller;

  @override
  Stream<EmbedPlaybackSnapshot> get changes => _changes.stream;

  @override
  Future<bool> play(Track track) async {
    if (track.sourceId.isEmpty) return false;

    await _valueSubscription?.cancel();
    _valueSubscription = _controller.stream.listen(
      _onValue,
      onError: (Object _) {
        _loaded = false;
      },
    );

    try {
      _position = Duration.zero;
      await _controller.loadVideoById(videoId: track.sourceId);
      _loaded = true;
      _startPositionTicker();
      _onValue(_controller.value);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> togglePlay() async {
    if (!_loaded) return false;
    final bool isPlaying = _controller.value.playerState == PlayerState.playing;
    if (isPlaying) {
      unawaited(_controller.pauseVideo());
    } else {
      unawaited(_controller.playVideo());
    }
    return !isPlaying;
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_loaded) return;
    _position = position;
    await _controller.seekTo(
      seconds: position.inMilliseconds / 1000,
      allowSeekAhead: true,
    );
  }

  void _onValue(YoutubePlayerValue value) {
    if (value.hasError) {
      _loaded = false;
      return;
    }

    if (_changes.isClosed) return;
    _changes.add(
      EmbedPlaybackSnapshot(
        isPlaying: value.playerState == PlayerState.playing,
        isBuffering: value.playerState == PlayerState.buffering,
        position: _position,
      ),
    );
  }

  /// The IFrame API only pushes position on state changes, which is too coarse
  /// for a smooth scrubber, so advance locally between updates.
  void _startPositionTicker() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_loaded || _changes.isClosed) return;
      if (_controller.value.playerState != PlayerState.playing) return;
      _position += const Duration(milliseconds: 500);
      if (_changes.isClosed) return;
      _changes.add(
        EmbedPlaybackSnapshot(
          isPlaying: true,
          isBuffering: false,
          position: _position,
        ),
      );
    });
  }

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _changes.close();
    await _controller.close();
  }
}
