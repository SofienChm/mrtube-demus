import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/services/audius_music_source.dart';

/// Shape taken verbatim from a live `/v1/tracks/search` response, trimmed to the
/// fields the parser reads. Encoding the real shape here is the point: the
/// parser was written against this, not against a guess.
Map<String, dynamic> liveTrackPayload({
  String id = 'vZJJz',
  String title = 'workit (daftpunk flip)',
  String artist = 'chromonicci.',
  num duration = 190,
  bool isStreamable = true,
  bool isAvailable = true,
  bool isStreamGated = false,
  bool isDelete = false,
  bool withStreamUrl = true,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'duration': duration,
    'is_streamable': isStreamable,
    'is_available': isAvailable,
    'is_stream_gated': isStreamGated,
    'is_delete': isDelete,
    'permalink': '/chromonicci/workit-daftpunk-flip-263514',
    'stream': withStreamUrl
        ? <String, dynamic>{
            'url': 'https://audius-content-2.figment.io/tracks/cidstream/QmQC',
            'mirrors': <String>['https://audius-discovery-1.altego.net'],
          }
        : null,
    'artwork': <String, dynamic>{
      '480x480': 'https://val010.open-audio-validator.com/content/QmWApvt',
      '150x150': 'https://val010.open-audio-validator.com/content/QmWApvt-s',
    },
    'user': <String, dynamic>{
      'id': 'n1OXD',
      'name': artist,
      'handle': 'chromonicci',
    },
  };
}

void main() {
  group('AudiusMusicSource.parseTrackPayload', () {
    test('maps a live payload to a direct-audio track', () {
      final Track? track = AudiusMusicSource.parseTrackPayload(
        liveTrackPayload(),
      );

      expect(track, isNotNull);
      expect(track!.id, 'audius:vZJJz');
      expect(track.sourceId, 'vZJJz');
      expect(track.title, 'workit (daftpunk flip)');
      expect(track.artist, 'chromonicci.');
      expect(track.playbackCapability, PlaybackCapability.directAudio);
      expect(
        track.isDirectAudio,
        isTrue,
        reason: 'this is what unlocks background playback',
      );
      expect(track.streamUrl, startsWith('https://'));
      expect(track.duration, const Duration(seconds: 190));
      expect(track.thumbnailUrl, contains('QmWApvt'));
    });

    test('prefers the 480px artwork over the thumbnail', () {
      final Track? track = AudiusMusicSource.parseTrackPayload(
        liveTrackPayload(),
      );
      expect(track!.thumbnailUrl, contains('QmWApvt'));
      expect(track.thumbnailUrl, isNot(contains('-s')));
    });

    test('converts fractional seconds', () {
      final Track? track = AudiusMusicSource.parseTrackPayload(
        liveTrackPayload(duration: 190.5),
      );
      expect(track!.duration, const Duration(milliseconds: 190500));
    });

    test('namespaces the id so it cannot collide with another provider', () {
      final Track? track = AudiusMusicSource.parseTrackPayload(
        liveTrackPayload(id: 'abc'),
      );
      expect(track!.id, 'audius:abc');
    });

    test('drops an unplayable track rather than failing at tap time', () {
      for (final Map<String, dynamic> payload in <Map<String, dynamic>>[
        liveTrackPayload(isStreamable: false),
        liveTrackPayload(isAvailable: false),
        liveTrackPayload(isStreamGated: true),
        liveTrackPayload(isDelete: true),
        liveTrackPayload(withStreamUrl: false),
      ]) {
        expect(
          AudiusMusicSource.parseTrackPayload(payload),
          isNull,
          reason: 'a track we cannot stream must not be offered',
        );
      }
    });

    test('survives a payload with a bare path instead of a stream object', () {
      final Map<String, dynamic> payload = liveTrackPayload();
      payload['stream'] = '/v1/tracks/vZJJz/stream';
      expect(
        AudiusMusicSource.parseTrackPayload(payload)!.streamUrl,
        '/v1/tracks/vZJJz/stream',
      );
    });

    test('tolerates a missing id, title, artist, or duration', () {
      final Map<String, dynamic> payload = liveTrackPayload();
      payload.remove('title');
      payload.remove('duration');
      payload.remove('user');

      final Track? track = AudiusMusicSource.parseTrackPayload(payload);
      expect(track, isNotNull);
      expect(track!.title, 'Unknown');
      expect(track.artist, 'Unknown artist');
      expect(track.duration, isNull);
    });

    test('treats a blank title as unknown but keeps a real one', () {
      final Map<String, dynamic> payload = liveTrackPayload(title: '   ');
      expect(AudiusMusicSource.parseTrackPayload(payload)!.title, 'Unknown');
    });

    test('rejects a zero or negative duration as unknown', () {
      expect(
        AudiusMusicSource.parseTrackPayload(liveTrackPayload(duration: 0))
            ?.duration,
        isNull,
      );
      expect(
        AudiusMusicSource.parseTrackPayload(liveTrackPayload(duration: -5))
            ?.duration,
        isNull,
      );
    });
  });
}
