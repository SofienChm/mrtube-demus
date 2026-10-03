import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/main.dart';

void main() {
  group('audio service configuration', () {
    // Constructing the config is itself the assertion: AudioServiceConfig
    // rejects an invalid combination with an assert, and asserts are compiled
    // out of release builds. Touching it in a test turns a device-only crash
    // into a failing test.
    test('is accepted by AudioServiceConfig', () {
      expect(AppDependencies.audioServiceConfig, isA<AudioServiceConfig>());
    });

    test('keeps the foreground service alive across a pause', () {
      // Android 12+ throws ForegroundServiceStartNotAllowedException if the
      // service drops out of the foreground while the app is backgrounded.
      expect(
        AppDependencies.audioServiceConfig.androidStopForegroundOnPause,
        isFalse,
      );
    });

    test('does not mark the notification ongoing', () {
      // audio_service asserts !androidNotificationOngoing ||
      // androidStopForegroundOnPause, and this app deliberately keeps the
      // service foreground on pause.
      expect(
        AppDependencies.audioServiceConfig.androidNotificationOngoing,
        isFalse,
      );
    });

    test('declares a notification channel', () {
      expect(
        AppDependencies.audioServiceConfig.androidNotificationChannelId,
        isNotEmpty,
      );
      expect(
        AppDependencies.audioServiceConfig.androidNotificationChannelName,
        isNotEmpty,
      );
    });
  });
}
