import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/models/track.dart';
import 'package:mrplay_new/core/search/search_ranker.dart';
import 'package:mrplay_new/core/search/search_sections.dart';

Track track(
  String title,
  String artist, {
  int plays = 0,
  int favourites = 0,
  DateTime? createdAt,
}) => Track(
  id: 'audius:$artist/$title',
  title: title,
  artist: artist,
  sourceId: '$artist/$title',
  thumbnailUrl: null,
  playCount: plays,
  favoriteCount: favourites,
  createdAt: createdAt,
);

void main() {
  group('SearchSections', () {
    test(
      'gives an artist query a top result, popular, and a channel group',
      () {
        final List<Track> ranked = SearchRanker.rank('samara', <Track>[
          track('Finnuh - Samara', 'finnuh', plays: 2004),
          track('Blue', 'Samara', plays: 500, createdAt: DateTime.utc(2024)),
          track('Red', 'Samara', plays: 900, createdAt: DateTime.utc(2025)),
          track('Green', 'Samara', plays: 700, createdAt: DateTime.utc(2026)),
          track('Old', 'Samara', plays: 10, createdAt: DateTime.utc(2023)),
          track('Himalayan Suite', 'Indus Rush', plays: 701),
        ]);

        final List<SearchSection> sections = SearchSections.build(
          'samara',
          ranked,
        );

        expect(sections, isNotEmpty);
        expect(sections.first, isA<TopResultSection>());
        expect((sections.first as TopResultSection).artist, 'Samara');
        // Newest leads, not the most-played.
        expect((sections.first as TopResultSection).track.title, 'Green');

        final List<String> titles = sections
            .whereType<TrackSection>()
            .map((TrackSection s) => s.title)
            .toList();
        expect(titles, contains('Popular'));
        expect(titles, contains('More from Samara'));
        expect(titles, contains('Other results'));
      },
    );

    test('shows exactly two popular tracks after the top result', () {
      final List<Track> ranked = SearchRanker.rank('samara', <Track>[
        for (int i = 0; i < 8; i++) track('Track $i', 'Samara', plays: i * 100),
      ]);

      final List<SearchSection> sections = SearchSections.build(
        'samara',
        ranked,
      );
      final TrackSection popular = sections
          .whereType<TrackSection>()
          .firstWhere((TrackSection s) => s.title == 'Popular');

      expect(popular.tracks, hasLength(2));
    });

    test('never repeats a track across sections', () {
      final List<Track> ranked = SearchRanker.rank('samara', <Track>[
        for (int i = 0; i < 10; i++)
          track('Track $i', 'Samara', plays: i * 100),
        track('Other', 'Someone Else', plays: 5),
      ]);

      final List<SearchSection> sections = SearchSections.build(
        'samara',
        ranked,
      );

      final List<String> ids = <String>[
        for (final SearchSection section in sections)
          if (section is TopResultSection)
            section.track.id
          else if (section is TrackSection)
            for (final Track t in section.tracks) t.id,
      ];

      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'a duplicated row would play the same track twice',
      );
      expect(ids, hasLength(11), reason: '10 by the artist plus 1 other');
    });

    test('falls back to one flat section for free-text queries', () {
      final List<Track> ranked = SearchRanker.rank('himalayan suite', <Track>[
        track('Appointment in Samara', 'Indus Rush', plays: 701),
        track('Himalayan Salt', 'Another', plays: 20),
      ]);

      final List<SearchSection> sections = SearchSections.build(
        'himalayan suite',
        ranked,
      );

      expect(sections, hasLength(1));
      expect(sections.single, isA<TrackSection>());
      expect((sections.single as TrackSection).tracks, hasLength(2));
    });

    test('omits groups that would be empty', () {
      final List<Track> ranked = SearchRanker.rank('samara', <Track>[
        track('Blue', 'Samara', plays: 10),
      ]);

      final List<SearchSection> sections = SearchSections.build(
        'samara',
        ranked,
      );

      final List<String> titles = sections
          .whereType<TrackSection>()
          .map((TrackSection s) => s.title)
          .toList();
      expect(titles, isNot(contains('Popular')));
      expect(titles, isNot(contains('Other results')));
    });

    test('returns nothing for no results', () {
      expect(SearchSections.build('samara', <Track>[]), isEmpty);
    });
  });
}
