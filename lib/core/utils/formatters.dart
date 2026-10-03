/// Display formatters. Kept free of intl so the common cases stay cheap enough
/// to call directly from `build`.
abstract final class Formatters {
  /// `m:ss` or `h:mm:ss`. Returns `--:--` for unknown durations so list rows
  /// never collapse to an empty string.
  static String duration(Duration? value) {
    if (value == null) return '--:--';
    final int totalSeconds = value.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    final String ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
    }
    return '$minutes:$ss';
  }

  /// Spoken-style remaining time for the full-screen player, e.g. `-2:31`.
  static String remaining(Duration position, Duration? total) {
    if (total == null) return '--:--';
    final Duration left = total - position;
    if (left.isNegative) return '0:00';
    return '-${duration(left)}';
  }

  /// Thousands-separated count, e.g. `1,204,533`.
  static String count(int value) {
    final String digits = value.abs().toString();
    final StringBuffer out = StringBuffer(value.isNegative ? '-' : '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// Coarse relative time for history rails: `now`, `12m`, `3h`, `2d`, `5w`.
  static String relative(DateTime timestamp, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final Duration delta = reference.difference(timestamp);
    if (delta.inSeconds < 60) return 'now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    if (delta.inHours < 24) return '${delta.inHours}h';
    if (delta.inDays < 7) return '${delta.inDays}d';
    if (delta.inDays < 365) return '${delta.inDays ~/ 7}w';
    return '${delta.inDays ~/ 365}y';
  }

  /// Byte size for the cache-cleaner screen.
  static String bytes(int value) {
    if (value < 1024) return '$value B';
    const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
    double size = value / 1024;
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }
}
