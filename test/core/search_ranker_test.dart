import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/search/search_ranker.dart';

Track track(
  String title,
  String artist, {
  int plays = 0,
  int favourites = 0,
  DateTime? createdAt,
}) => Track(
  id: 'audius:$title-$artist',
  title: title,
  artist: artist,
  sourceId: '$title-$artist',
  thumbnailUrl: null,
  playCount: plays,
  favoriteCount: favourites,
  createdAt: createdAt,
);

void main() {
  group('SearchRanker', () {
    test('puts the artist the user typed above tracks that mention them', () {
      // The real Audius response for "samara": provider relevance puts a track
      // merely titled "Samara" and an unrelated "Appointment in Samara" first.
      final List<Track> results = <Track>[
        track('Finnuh - Samara', 'finnuh', plays: 2004),
        track('Samara', 'J.s.R', plays: 3048),
        track(
          'Himalayan Suite - Appointment in Samara',
          'Indus Rush',
          plays: 701,
        ),
      ];

      final List<Track> ranked = SearchRanker.rank('samara', results);

      expect(ranked.first.title, 'Samara');
      expect(
        ranked.map((Track t) => t.title),
        isNot(
          equals(<String>[
            'Finnuh - Samara',
            'Samara',
            'Himalayan Suite - Appointment in Samara',
          ]),
        ),
      );
    });

    test('an exact artist match outranks a higher play count', () {
      final List<Track> results = <Track>[
        track('Some Song', 'Other Artist', plays: 900000),
        track('Anything', 'Samara', plays: 12),
      ];

      expect(SearchRanker.rank('samara', results).first.artist, 'Samara');
    });

    test('ranks the title match second when the artist does not match', () {
      final List<Track> results = <Track>[
        track('Unrelated Song', 'Someone Else', plays: 5000),
        track('Appointment in Samara', 'Indus Rush', plays: 10),
      ];

      expect(
        SearchRanker.rank('samara', results).first.title,
        'Appointment in Samara',
      );
    });

    test('orders same-tier results by popularity', () {
      final List<Track> results = <Track>[
        track('One', 'Samara', plays: 100),
        track('Two', 'Samara', plays: 900),
        track('Three', 'Samara', plays: 400),
      ];

      expect(
        SearchRanker.rank(
          'samara',
          results,
        ).map((Track t) => t.playCount).toList(),
        <int>[900, 400, 100],
      );
    });

    test('is case, accent, and punctuation insensitive', () {
      expect(SearchRanker.score('cafe', track('x', 'Café')), greaterThan(500));
      expect(SearchRanker.score('CAFE', track('x', 'cafe')), greaterThan(500));
      expect(
        SearchRanker.score('ac dc', track('x', 'AC/DC')),
        greaterThan(500),
      );
      expect(SearchRanker.score('  samara  ', track('x', 'Samara')), 1000);
    });

    test('requires a whole word, not a substring', () {
      // "art" must not drag in "partial".
      expect(SearchRanker.score('art', track('x', 'partial')), 0);
      expect(
        SearchRanker.score('art', track('x', 'The Art')),
        greaterThan(500),
      );
    });

    test('keeps an artist match for a multi-word query', () {
      // "samara beat" must still surface Samara even though "beat" matches
      // nothing, so the artist tier has to survive extra query words.
      final Track byArtist = track('Blue Lights', 'Samara');
      expect(
        SearchRanker.score('samara beat', byArtist),
        greaterThanOrEqualTo(500),
      );

      final Track exactArtist = track('Blue Lights', 'Samara');
      expect(
        SearchRanker.score('samara', exactArtist),
        greaterThan(SearchRanker.score('samara beat', byArtist)),
      );
    });

    test('does not match when a query token appears nowhere', () {
      // "samara" is absent from both fields here, so no rule may fire.
      final Track partial = track('Blue Lights', 'Someone Else');
      expect(SearchRanker.score('samara blue', partial), 0);
    });

    test('matches when every token is present across artist and title', () {
      final Track spread = track('Blue Lights', 'Samara');
      expect(SearchRanker.score('samara blue', spread), greaterThan(0));
    });

    test('an empty query does not reorder by score', () {
      final List<Track> results = <Track>[
        track('A', 'X', plays: 1),
        track('B', 'Y', plays: 2),
      ];
      expect(SearchRanker.rank('', results).length, 2);
      expect(SearchRanker.score('', results.first), 0);
    });

    test('preserves provider order when nothing scores', () {
      final List<Track> results = <Track>[
        track('A', 'X'),
        track('B', 'Y'),
        track('C', 'Z'),
      ];

      expect(
        SearchRanker.rank(
          'nothing matches this',
          results,
        ).map((Track t) => t.title),
        <String>['A', 'B', 'C'],
      );
    });

    test('identifies the artist a query refers to', () {
      final List<Track> results = <Track>[
        track('Finnuh - Samara', 'finnuh'),
        track('Samara', 'Samara', plays: 3048),
      ];

      expect(SearchRanker.matchedArtist('samara', results), 'Samara');
      expect(SearchRanker.matchedArtist('zzz nothing', results), isNull);
    });

    test('surfaces an artist newest release first within a tier', () {
      final DateTime older = DateTime.utc(2024);
      final DateTime newer = DateTime.utc(2026);
      final List<Track> results = <Track>[
        track('Older', 'Samara', plays: 50, createdAt: older),
        track('Newer', 'Samara', plays: 50, createdAt: newer),
      ];

      expect(SearchRanker.rank('samara', results).first.title, 'Newer');
    });
  });
}
