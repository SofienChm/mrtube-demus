import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/models/artist_summary.dart';
import 'package:mrplay_new/core/search/artist_user_ranker.dart';

ArtistSummary artist(
  String name, {
  String? handle,
  String id = 'u1',
  int followers = 0,
  int tracks = 0,
}) => ArtistSummary(
  id: 'audius:$id',
  sourceId: id,
  name: name,
  handle: handle,
  followerCount: followers,
  trackCount: tracks,
);

void main() {
  group('ArtistUserRanker', () {
    test('promotes an exact name match above a much more popular impostor', () {
      // This is the real shape of the bug: the provider returns an unrelated
      // 87k-follower account as its top hit for an exact-name query.
      final List<ArtistSummary> ranked = ArtistUserRanker.rank(
        'samara',
        <ArtistSummary>[
          artist(
            'Alina Baraz',
            handle: 'alinabaraz',
            followers: 87687,
            id: 'a',
          ),
          artist('Samara', handle: 'jmar_', followers: 30, tracks: 3, id: 'b'),
        ],
      );

      expect(ranked.first.name, 'Samara');
      expect(ranked.first.sourceId, 'b');
    });

    test('ignores follower count across different name matches', () {
      // Both are real name matches; popularity is a legitimate tiebreak here.
      final List<ArtistSummary> ranked = ArtistUserRanker.rank(
        'samara',
        <ArtistSummary>[
          artist('Samara', handle: 'jmar_', followers: 30, id: 'b'),
          artist('Samara', handle: 'Samara', followers: 7, id: 'c'),
        ],
      );

      expect(ranked.first.sourceId, 'b');
    });

    test('treats an exact handle match as a strong signal', () {
      final List<ArtistSummary> ranked = ArtistUserRanker.rank(
        'jmar_',
        <ArtistSummary>[
          artist('Someone Else', followers: 90000, id: 'x'),
          artist('Samara', handle: 'jmar_', followers: 30, id: 'b'),
        ],
      );

      expect(ranked.first.sourceId, 'b');
    });

    test('matches case and diacritics insensitively', () {
      expect(
        ArtistUserRanker.score('cafe', artist('Café')),
        ArtistUserRanker.score('CAFÉ', artist('cafe')),
      );
      expect(ArtistUserRanker.score('cafe', artist('Café')), 1000);
    });

    test('scores an unrelated artist as zero', () {
      expect(ArtistUserRanker.score('samara', artist('Alina Baraz')), 0);
    });

    test('ranks a partial name match below an exact one', () {
      final List<ArtistSummary> ranked = ArtistUserRanker.rank(
        'samara',
        <ArtistSummary>[
          artist('Samara Almeida', followers: 99999, id: 'p'),
          artist('Samara', followers: 1, id: 'e'),
        ],
      );

      expect(ranked.first.sourceId, 'e');
      expect(ranked.last.sourceId, 'p');
    });

    test('bestMatch only returns an exact name match', () {
      final List<ArtistSummary> results = <ArtistSummary>[
        artist('Samara Almeida', id: 'p'),
        artist('Samara', id: 'e'),
      ];

      expect(ArtistUserRanker.bestMatch('samara', results)?.sourceId, 'e');
      expect(
        ArtistUserRanker.bestMatch('someone-else', results),
        isNull,
        reason:
            'guessing a channel from a partial match risks showing a '
            'stranger',
      );
    });

    test('bestMatch returns null for an empty query', () {
      expect(
        ArtistUserRanker.bestMatch('  ', <ArtistSummary>[artist('Samara')]),
        isNull,
      );
    });

    test('score is zero for an empty query', () {
      expect(ArtistUserRanker.score('', artist('Samara')), 0);
    });

    test('ranking is stable for equally relevant artists', () {
      final List<ArtistSummary> results = <ArtistSummary>[
        artist('Samara', id: 'first'),
        artist('Samara', id: 'second'),
      ];

      expect(
        ArtistUserRanker.rank(
          'samara',
          results,
        ).map((ArtistSummary a) => a.sourceId),
        <String>['first', 'second'],
      );
    });

    test('isSameArtist compares normalised names', () {
      final ArtistSummary a = artist('Samara', id: 'x');
      expect(ArtistUserRanker.isSameArtist(a, 'samara'), isTrue);
      expect(ArtistUserRanker.isSameArtist(a, 'Samara  '), isTrue);
      expect(ArtistUserRanker.isSameArtist(a, 'Samara Almeida'), isFalse);
      expect(ArtistUserRanker.isSameArtist(a, null), isFalse);
    });
  });
}
