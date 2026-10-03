import '../models/track.dart';
import 'search_ranker.dart';

/// A titled group of results, or a single highlighted result.
sealed class SearchSection {
  const SearchSection();
}

/// The single best match, shown large at the top.
final class TopResultSection extends SearchSection {
  const TopResultSection({required this.track, required this.artist});

  final Track track;

  /// The artist the query resolved to, if any. Drives the "see all" affordance.
  final String? artist;
}

/// A titled row of tracks.
final class TrackSection extends SearchSection {
  const TrackSection({required this.title, required this.tracks});

  final String title;
  final List<Track> tracks;
}

/// Groups ranked results into the layout a listener expects from a music app.
///
/// A provider's flat relevance list answers "what matches these words". This
/// answers "who/what did they mean": when a query names an artist, that artist
/// gets the top slot, their popular tracks follow, their remaining tracks are
/// grouped under their name, and everything else is demoted below.
///
/// When nothing matches an artist the input is flattened into one section, so
/// free-text queries still render normally.
abstract final class SearchSections {
  static List<SearchSection> build(String query, List<Track> ranked) {
    if (ranked.isEmpty) return const <SearchSection>[];

    final String? artist = SearchRanker.matchedArtist(query, ranked);
    if (artist == null) {
      return <SearchSection>[TrackSection(title: 'Results', tracks: ranked)];
    }

    final List<Track> byArtist = <Track>[
      for (final Track t in ranked)
        if (_sameArtist(t.artist, artist)) t,
    ];
    final List<Track> others = <Track>[
      for (final Track t in ranked)
        if (!_sameArtist(t.artist, artist)) t,
    ];

    if (byArtist.isEmpty) {
      return <SearchSection>[TrackSection(title: 'Results', tracks: ranked)];
    }

    // Newest release leads, because "search an artist" most often means "play
    // their latest". [SearchRanker.rank] orders an artist tier by popularity, so
    // recency has to be recovered explicitly here rather than read off the front
    // of the list. Falls back to the top-ranked track when nothing carries a
    // date.
    Track newest = byArtist.first;
    DateTime? newestDate = newest.createdAt;
    for (final Track candidate in byArtist) {
      final DateTime? date = candidate.createdAt;
      if (date == null) continue;
      if (newestDate == null || date.isAfter(newestDate)) {
        newest = candidate;
        newestDate = date;
      }
    }
    final List<Track> popular =
        <Track>[
          for (final Track t in byArtist)
            if (t.id != newest.id) t,
        ]..sort((Track a, Track b) {
          final int byPlays = b.playCount.compareTo(a.playCount);
          if (byPlays != 0) return byPlays;
          return b.favoriteCount.compareTo(a.favoriteCount);
        });

    final List<Track> headline = popular.take(2).toList(growable: false);
    final Set<String> used = <String>{
      for (final Track t in headline) t.id,
      newest.id,
    };
    final List<Track> more = <Track>[
      for (final Track t in byArtist)
        if (!used.contains(t.id)) t,
    ];

    return <SearchSection>[
      TopResultSection(track: newest, artist: artist),
      if (headline.isNotEmpty) TrackSection(title: 'Popular', tracks: headline),
      if (more.isNotEmpty)
        TrackSection(title: 'More from $artist', tracks: more),
      if (others.isNotEmpty)
        TrackSection(title: 'Other results', tracks: others),
    ];
  }

  /// Compares artist names loosely, because providers disagree on spacing and
  /// capitalisation between the search and detail endpoints.
  static bool _sameArtist(String a, String b) =>
      a.toLowerCase().trim() == b.toLowerCase().trim();
}
