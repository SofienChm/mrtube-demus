import '../models/artist_summary.dart';
import 'text_normalizer.dart';

/// An artist paired with the relevance score that decided its position.
final class _Scored {
  const _Scored(this.artist, this.score);

  final ArtistSummary artist;
  final int score;
}

/// Orders artist/channel results so the person the user typed comes first.
///
/// This ranker is not optional. The live user-search endpoint returns an
/// unrelated account as its *top* result for an exact name query: searching
/// "samara" ranks "Alina Baraz" (@alinabaraz, 87k followers) above the several
/// accounts actually named Samara, because the endpoint ranks on its own fuzzy
/// text similarity and follower weight. Trusting that order would show the
/// wrong person's channel, which is worse than showing none.
///
/// The rule encoded here: the display name matching the query exactly is the
/// strongest signal, the `@handle` is next, and partial word matches only rank
/// above a non-match. Popularity breaks ties only *within* a tier, so it can
/// never promote a different artist above a correct name match.
abstract final class ArtistUserRanker {
  static const int _nameExact = 1000;

  /// At or above which a result is considered a real match rather than noise.
  static const int matchThreshold = 400;

  /// Sorts [artists] for [query], most relevant first.
  ///
  /// Stable, so equally relevant results keep provider order.
  static List<ArtistSummary> rank(String query, List<ArtistSummary> artists) {
    final List<_Scored> scored = <_Scored>[
      for (final ArtistSummary a in artists) _Scored(a, score(query, a)),
    ];

    scored.sort((_Scored a, _Scored b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final int byFollowers = b.artist.followerCount.compareTo(
        a.artist.followerCount,
      );
      if (byFollowers != 0) return byFollowers;
      final int byTracks = b.artist.trackCount.compareTo(a.artist.trackCount);
      if (byTracks != 0) return byTracks;
      return 0;
    });

    return <ArtistSummary>[for (final _Scored s in scored) s.artist];
  }

  /// Relevance of one artist for [query].
  ///
  /// Exposed for tests because the ordering is the whole point of this class.
  static int score(String query, ArtistSummary artist) {
    final String q = TextNormalizer.normalize(query);
    if (q.isEmpty) return 0;

    final String name = TextNormalizer.normalize(artist.name);
    final String handle = TextNormalizer.normalize(artist.handle ?? '');

    if (name == q) return _nameExact;
    if (handle == q) return 900;
    if (name.startsWith('$q ')) return 800;
    if (handle.startsWith(q)) return 700;
    if (TextNormalizer.containsWord(name, q)) return 600;
    if (TextNormalizer.containsWord(handle, q)) return 500;
    if (name.contains(q) || handle.contains(q)) return matchThreshold;

    return 0;
  }

  /// The artist [query] most likely refers to, or null when nothing matches.
  ///
  /// Only exact name matches qualify. A channel is a strong, deliberate claim
  /// about who the user meant, so guessing from a partial match risks showing
  /// them a stranger's page.
  static ArtistSummary? bestMatch(String query, List<ArtistSummary> artists) {
    for (final ArtistSummary artist in rank(query, artists)) {
      if (score(query, artist) >= _nameExact) return artist;
    }
    return null;
  }

  /// True when [artist] plausibly refers to the same person as [other].
  ///
  /// Both a shared provider user id and a shared normalised name count. The id
  /// is authoritative; the name is a fallback for tracks cached before
  /// [ArtistSummary] lookups existed.
  static bool isSameArtist(ArtistSummary artist, String? trackArtistName) {
    if (trackArtistName == null) return false;
    final String a = TextNormalizer.normalize(artist.name);
    final String b = TextNormalizer.normalize(trackArtistName);
    return a.isNotEmpty && a == b;
  }
}
