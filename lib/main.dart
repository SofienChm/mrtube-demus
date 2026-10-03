import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/constants/app_theme.dart';
import 'core/models/track.dart';
import 'core/services/audio_player_handler.dart';
import 'core/services/audius_music_source.dart';
import 'core/services/database_service.dart';
import 'core/services/music_source.dart';
import 'core/services/track_repository.dart';
import 'core/services/youtube_music_source.dart';
import 'features/bootstrap/view/bootstrap_gate.dart';
import 'features/player/data/youtube_embed_controller.dart';

/// Objects that must outlive individual widgets.
///
/// `AudioService.init` returns a handler bound to a separate isolate on Android,
/// so it cannot be created inside a `BlocProvider` and torn down with a widget
/// tree. It is created once here and injected downward.
final class AppDependencies {
  AppDependencies._({
    required this.database,
    required this.repository,
    required this.audioHandler,
    required this.embedController,
  });

  final DatabaseService database;
  final TrackRepository repository;
  final AudioPlayerHandler audioHandler;
  final YoutubeEmbedController embedController;

  /// API key for YouTube Data API v3 metadata, supplied at build time:
  ///
  /// ```
  /// flutter build apk --dart-define=YOUTUBE_API_KEY=...
  /// ```
  ///
  /// Absent in debug so the app still boots and serves cached content rather
  /// than throwing during startup.
  static const String youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  /// Longest a single bootstrap stage may take before it is treated as failed.
  ///
  /// `AudioService.init` binds to a platform service; if that handshake stalls
  /// the future never completes, so without a ceiling startup would hang on a
  /// blank screen indefinitely.
  static const Duration stageTimeout = Duration(seconds: 25);

  /// Reports which stage is running, so a failure can name itself.
  static Future<AppDependencies> bootstrap({
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('opening local library');
    final DatabaseService database = await DatabaseService.init().timeout(
      stageTimeout,
      onTimeout: () =>
          throw const BootstrapFailure('Opening the local library timed out.'),
    );

    // Ordered by preference. Audius leads because it is the only source that can
    // produce direct audio, so it is what makes background playback and
    // lock-screen controls work. YouTube stays behind it for breadth of catalog
    // and plays through the official embed player.
    final List<MusicSource> sources = <MusicSource>[
      AudiusMusicSource(appName: AudiusMusicSource.defaultAppName),
      if (youtubeApiKey.isNotEmpty) YouTubeMusicSource(apiKey: youtubeApiKey),
    ];

    onStage?.call('connecting to the audio service');
    final AudioPlayerHandler audioHandler = await _initAudioHandler(database)
        .timeout(
          stageTimeout,
          onTimeout: () => throw const BootstrapFailure(
            'The audio service did not respond.',
          ),
        );

    onStage?.call('starting playback engine');
    return AppDependencies._(
      database: database,
      repository: TrackRepository(database: database, sources: sources),
      audioHandler: audioHandler,
      embedController: YoutubeEmbedController(),
    );
  }

  /// Audio service configuration.
  ///
  /// Exposed as a field so tests can construct it. `AudioServiceConfig`
  /// validates its own arguments with `assert`, which only fires in debug
  /// builds, so an invalid combination otherwise reaches a device before
  /// anything notices.
  static final AudioServiceConfig audioServiceConfig = AudioServiceConfig(
    androidNotificationChannelId: 'com.mrplay.mrplay_new.audio',
    androidNotificationChannelName: 'Music playback',

    // Keep the service in the foreground across a pause. Without this,
    // Android 12+ throws ForegroundServiceStartNotAllowedException as soon as
    // the user pauses and then backgrounds the app.
    androidStopForegroundOnPause: false,

    // Must stay false while androidStopForegroundOnPause is false:
    // audio_service asserts the two are mutually exclusive, because the
    // notification stays up anyway while the service remains foreground.
    androidNotificationOngoing: false,
  );

  static Future<AudioPlayerHandler> _initAudioHandler(
    DatabaseService database,
  ) {
    final _DatabaseHooks hooks = _DatabaseHooks(database);

    return AudioService.init<AudioPlayerHandler>(
      builder: () => AudioPlayerHandler(hooks: hooks),
      config: audioServiceConfig,
    );
  }
}

/// A bootstrap step that could not complete.
///
/// Carries a message meant to be read on the device, because when startup fails
/// without a debugger attached this string is the only diagnostic there is.
final class BootstrapFailure implements Exception {
  const BootstrapFailure(this.message);

  final String message;

  @override
  String toString() => 'BootstrapFailure: $message';
}

/// Adapts [DatabaseService] to the narrow interface the handler depends on.
final class _DatabaseHooks implements DatabaseServiceHooks {
  const _DatabaseHooks(this._database);

  final DatabaseService _database;

  @override
  Future<void> onTrackStarted(String trackId) => _database.recordPlay(trackId);

  @override
  Future<Track?> resolveTrack(String trackId) async {
    final Track? cached = _database.getTrack(trackId);
    if (cached == null || cached.streamUrl == null) return null;
    return cached;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);

  // Rendered before dependencies exist so a bootstrap failure shows a readable
  // error instead of a black screen.
  runApp(const BootstrapGate());
}
