import '../models/track.dart';

/// A track paired with the relevance score that decided its position.
final class _Scored {
  const _Scored(this.track, this.score);

  final Track track;
  final int score;
}

/// Relevance at or above which a match is attributed to the artist field.
const int _artistTitlePrefix = 500;

/// Orders search results so the thing the user typed comes first.
///
/// Providers order by their own notion of relevance, which optimises for text
/// matches rather than intent. Searching an artist's name reliably surfaces
/// tracks that merely *mention* that name in their title ahead of the artist
/// themself, because those titles match the keyword harder.
///
/// The rule this encodes: a query that names an artist is a request for that
/// artist. Artist identity therefore outweighs title matches, and popularity
/// breaks ties within the same tier.
abstract final class SearchRanker {
  /// Above any title-based score, so an exact artist match always wins.
  static const int _artistExact = 1000;

  /// Sorts [tracks] for [query], most relevant first.
  ///
  /// The sort is stable, so tracks the provider considered equally relevant keep
  /// their original relative order instead of shuffling between identical
  /// queries.
  static List<Track> rank(String query, List<Track> tracks) {
    final List<_Scored> scored = <_Scored>[
      for (final Track track in tracks) _Scored(track, score(query, track)),
    ];

    scored.sort((_Scored a, _Scored b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Within a tier, popularity decides.
      final int byPlays = b.track.playCount.compareTo(a.track.playCount);
      if (byPlays != 0) return byPlays;
      final int byFavourites = b.track.favoriteCount.compareTo(
        a.track.favoriteCount,
      );
      if (byFavourites != 0) return byFavourites;
      // Newest first, so an artist's latest release leads their own tracks.
      final DateTime? aCreated = a.track.createdAt;
      final DateTime? bCreated = b.track.createdAt;
      if (aCreated != null && bCreated != null) {
        final int byDate = bCreated.compareTo(aCreated);
        if (byDate != 0) return byDate;
      }
      return 0;
    });

    return <Track>[for (final _Scored s in scored) s.track];
  }

  /// Relevance of [track] for [query]. Higher is better.
  static int score(String query, Track track) {
    final String q = _normalize(query);
    if (q.isEmpty) return 0;

    final String artist = _normalize(track.artist);
    final String title = _normalize(track.title);

    // Artist identity, strongest first. These deliberately outrank every title
    // match: typing an artist's name means "this artist", not "any track whose
    // title happens to contain the word".
    if (artist == q) return _artistExact;
    if (_startsWith(artist, q)) return 800;
    if (artist.startsWith(q) && artist.length > q.length) return 700;
    if (_containsWord(artist, q)) return 600;
    if (q.startsWith(artist) && artist.isNotEmpty) return _artistTitlePrefix;

    // Title matches.
    if (title == q) return 400;
    if (_startsWith(title, q)) return 300;
    if (_containsWord(title, q)) return 200;

    // Every token present somewhere. Covers "samara rapper" style queries.
    final List<String> tokens = q
        .split(' ')
        .where((String t) => t.isNotEmpty)
        .toList();
    if (tokens.isNotEmpty &&
        tokens.every(
          (String token) =>
              _containsWord(artist, token) || _containsWord(title, token),
        )) {
      return 100;
    }

    return 0;
  }

  /// The artist [query] most likely refers to, or null if nothing matches.
  ///
  /// Used to decide whether results should be grouped under that artist.
  static String? matchedArtist(String query, List<Track> tracks) {
    final String q = _normalize(query);
    if (q.isEmpty) return null;

    for (final Track track in tracks) {
      if (score(query, track) >= _artistTitlePrefix) {
        return track.artist;
      }
    }
    return null;
  }

  /// Lowercase, strip diacritics, drop punctuation, collapse whitespace.
  ///
  /// Providers are inconsistent about accents and separators ("Café", "cafe",
  /// "C.afe" should all match the same query).
  static String _normalize(String input) {
    final String lower = input.toLowerCase().trim();
    final String stripped = _stripDiacritics(lower);
    final String noPunctuation = stripped.replaceAll(
      RegExp(r'[^a-z0-9\u00C0-\u024F ]+'),
      ' ',
    );
    return noPunctuation.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _stripDiacritics(String input) {
    const String from = 'áàâäãåéèêëíìîïóòôöõúùûüñçšž';
    const String to = 'aaaaaaeeeeiiiiooooouuuuncsz';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in input.runes) {
      final String char = String.fromCharCode(rune);
      final int index = from.indexOf(char);
      buffer.write(index >= 0 ? to[index] : char);
    }
    return buffer.toString();
  }

  static bool _startsWith(String value, String prefix) =>
      value.startsWith(prefix);

  /// Whole-word containment, so "art" does not match "partial".
  static bool _containsWord(String value, String word) {
    if (word.isEmpty) return false;
    if (!value.contains(word)) return false;
    final int at = value.indexOf(word);
    if (at == 0) return true;
    if (at + word.length == value.length) return true;
    return value[at - 1] == ' ' && value[at + word.length] == ' ';
  }
}
