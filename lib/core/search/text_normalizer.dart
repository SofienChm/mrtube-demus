/// Text normalisation shared by every relevance ranker.
///
/// Search matching fails in two ways that look like "no results": accented and
/// unaccented spellings that should be equal are not ("Café" vs "cafe"), and a
/// keyword buried inside a longer word counts as a match ("art" inside
/// "partial"). Both rankers need the same answer, so it lives here rather than
/// being reimplemented per provider.
abstract final class TextNormalizer {
  /// Lowercase, strip diacritics, drop punctuation, collapse whitespace.
  static String normalize(String input) {
    final String lower = input.toLowerCase().trim();
    final String stripped = _stripDiacritics(lower);
    final String noPunctuation = stripped.replaceAll(
      RegExp(r'[^a-z0-9\u00C0-\u024F ]+'),
      ' ',
    );
    return noPunctuation.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Whole-word containment, so "art" does not match "partial".
  static bool containsWord(String value, String word) {
    if (word.isEmpty) return false;
    if (!value.contains(word)) return false;
    int at = value.indexOf(word);
    while (at >= 0) {
      final bool leftOk = at == 0 || value[at - 1] == ' ';
      final int end = at + word.length;
      final bool rightOk = end == value.length || value[end] == ' ';
      if (leftOk && rightOk) return true;
      at = value.indexOf(word, at + 1);
    }
    return false;
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
}
