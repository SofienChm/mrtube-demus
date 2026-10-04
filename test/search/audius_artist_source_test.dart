import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/models/artist_summary.dart';
import 'package:mrplay_new/core/services/audius_music_source.dart';

void main() {
  group('AudiusMusicSource.parseArtistPayload', () {
    // Trimmed from the live `/v1/users/search` response for "samara". Every field
    // name here was verified against the real API rather than assumed.
    final Map<String, dynamic> user = <String, dynamic>{
      'id': 'd69VM',
      'user_id': 1967570,
      'name': 'Samara',
      'handle': 'jmar_',
      'profile_picture': <String, dynamic>{
        '1000x1000': 'https://cdn.test/avatar-1000.jpg',
        '480x480': 'https://cdn.test/avatar-480.jpg',
      },
      'cover_photo': <String, dynamic>{
        '2000x': 'https://cdn.test/cover-2000.jpg',
        '600x': 'https://cdn.test/cover-600.jpg',
      },
      // The plural field exists in the payload but is always null; reading it
      // silently reports every artist as having zero followers.
      'followers_count': null,
      'follower_count': 30,
      'track_count': 3,
      'is_verified': true,
      'bio': 'my bio',
      'location': 'Paris',
    };

    test('maps identity and counts', () {
      final ArtistSummary? artist = AudiusMusicSource.parseArtistPayload(user);

      expect(artist, isNotNull);
      expect(artist!.id, 'audius:d69VM');
      expect(artist.sourceId, 'd69VM');
      expect(artist.name, 'Samara');
      expect(artist.handle, 'jmar_');
      expect(artist.handleLabel, '@jmar_');
      expect(artist.followerCount, 30);
      expect(artist.trackCount, 3);
      expect(artist.isVerified, isTrue);
      expect(artist.bio, 'my bio');
      expect(artist.location, 'Paris');
    });

    test('reads follower_count, not the null followers_count', () {
      final ArtistSummary artist = AudiusMusicSource.parseArtistPayload(user)!;
      expect(user['followers_count'], isNull);
      expect(artist.followerCount, 30);
    });

    test('prefers a mid-size avatar', () {
      expect(
        AudiusMusicSource.parseArtistPayload(user)!.avatarUrl,
        'https://cdn.test/avatar-480.jpg',
      );
    });

    test('picks the largest cover photo, which is keyed by width alone', () {
      expect(
        AudiusMusicSource.parseArtistPayload(user)!.coverUrl,
        'https://cdn.test/cover-2000.jpg',
      );
    });

    test('rejects a payload with no id', () {
      expect(
        AudiusMusicSource.parseArtistPayload(<String, dynamic>{'name': 'X'}),
        isNull,
      );
    });

    test('falls back to a placeholder name rather than an empty row', () {
      final Map<String, dynamic> blank = <String, dynamic>{
        'id': 'abc',
        'name': '   ',
      };
      expect(
        AudiusMusicSource.parseArtistPayload(blank)!.name,
        'Unknown artist',
      );
    });

    test('treats the placeholder bio "-" as absent', () {
      final ArtistSummary artist = AudiusMusicSource.parseArtistPayload(
        <String, dynamic>{'id': 'abc', 'name': 'X', 'bio': '-'},
      )!;
      expect(artist.bio, isNull);
    });

    test('reports zero followers for an account that genuinely has none', () {
      final ArtistSummary artist = AudiusMusicSource.parseArtistPayload(
        <String, dynamic>{'id': 'abc', 'name': 'X', 'follower_count': 0},
      )!;
      expect(artist.followerCount, 0);
      expect(artist.handleLabel, '');
    });
  });

  group('AudiusMusicSource.parseTrackPayload', () {
    test('captures the uploader id so a track can lead back to its channel', () {
      // `user.id` is the CID form, which is what a user-search result joins on.
      final Map<String, dynamic> track = <String, dynamic>{
        'id': '7W399',
        'title': 'Samara - Location (Audio)',
        'duration': 212,
        'play_count': 2634,
        'favorite_count': 4,
        'created_at': '2022-11-18T17:01:00Z',
        'is_streamable': true,
        'stream': <String, dynamic>{'url': 'https://cdn.test/s.mp3'},
        'user': <String, dynamic>{
          'id': 'd69VM',
          'user_id': 1967570,
          'name': 'Samara',
          'handle': 'jmar_',
        },
      };

      final parsed = AudiusMusicSource.parseTrackPayload(track);
      expect(parsed, isNotNull);
      expect(parsed!.userId, 'd69VM');
      expect(parsed.artist, 'Samara');
      expect(parsed.playCount, 2634);
      expect(parsed.createdAt, DateTime.utc(2022, 11, 18, 17, 1));
    });

    test('leaves userId null when the payload has no uploader', () {
      final Map<String, dynamic> track = <String, dynamic>{
        'id': 'x',
        'title': 'T',
        'is_streamable': true,
        'stream': <String, dynamic>{'url': 'https://cdn.test/s.mp3'},
        'user': <String, dynamic>{'name': 'Nameless'},
      };
      expect(AudiusMusicSource.parseTrackPayload(track)!.userId, isNull);
    });

    test('falls back to a numeric user id when the CID is absent', () {
      final Map<String, dynamic> track = <String, dynamic>{
        'id': 'x',
        'title': 'T',
        'is_streamable': true,
        'stream': <String, dynamic>{'url': 'https://cdn.test/s.mp3'},
        'user': <String, dynamic>{'user_id': 1967570, 'name': 'Samara'},
      };
      expect(AudiusMusicSource.parseTrackPayload(track)!.userId, '1967570');
    });
  });
}
