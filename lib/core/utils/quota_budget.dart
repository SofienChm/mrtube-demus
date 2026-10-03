import 'dart:math';

/// Local mirror of a provider's daily allowance, so the app can fail loudly and
/// locally instead of discovering an exhausted quota through HTTP 403s.
///
/// This exists because YouTube's `search.list` has a hard default limit of 100
/// calls per day *project-wide*, shared by every user. There is no client-side
/// workaround: the only real levers are caching (so repeated queries cost
/// nothing) and refusing politely once the budget is gone, rather than letting
/// every user see a raw quota error.
///
/// Note the window resets at midnight UTC. YouTube actually resets at midnight
/// Pacific; the up-to-7h skew is absorbed by the fact that the budget is an
/// estimate the user can see and we never spend more than the limit.
final class QuotaBudget {
  QuotaBudget({required this.dailyLimit, DateTime? now})
    : _window = _dayOf((now ?? DateTime.now()).toUtc()) {
    // Pin the clock whenever a time is injected. Setting [_window] alone is not
    // enough: the first lazy roll would otherwise discard the injected date and
    // reset the counter against the wall clock.
    if (now != null) _clockOverride = now.toUtc();
  }

  /// Injectable `now` in tests; production passes nothing and gets [DateTime].
  final int dailyLimit;

  /// Calls consumed in the current window.
  int _spent = 0;

  /// UTC date that [_spent] refers to. Crossing into a new date resets.
  DateTime _window;

  /// Sticky clock override, set the first time a caller injects `now`.
  ///
  /// Every read path ([remaining], [isExhausted], [isTight]) rolls the window
  /// lazily, so the injected time has to outlive the single call that supplied
  /// it. Without this, [tryConsume] would roll against `now` and the `isExhausted`
  /// check immediately after it would roll again against the wall clock,
  /// silently resetting the counter.
  DateTime? _clockOverride;

  static DateTime _dayOf(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Calls remaining in the current window.
  int get remaining {
    _rollIfNewDay();
    return max(0, dailyLimit - _spent);
  }

  double get fractionRemaining {
    final int left = remaining;
    return dailyLimit == 0 ? 0 : left / dailyLimit;
  }

  bool get isExhausted => remaining == 0;

  /// True once the budget is low enough that the UI should start steering
  /// users toward cached results.
  bool get isTight {
    _rollIfNewDay();
    return fractionRemaining <= 0.1;
  }

  /// Consumes one call if available. Returns false when the window is spent,
  /// which the caller should surface as a cache-only result rather than an
  /// error dialog.
  bool tryConsume([DateTime? now]) {
    _rollIfNewDay(now);
    if (isExhausted) return false;
    _spent++;
    return true;
  }

  /// Gives one unit back. Called when a call was consumed but never reached the
  /// provider (DNS failure, socket error, timeout), so a flaky network cannot
  /// permanently shrink the day's allowance.
  ///
  /// Deliberately not called for HTTP 4xx: those are real, billed requests.
  void refund() {
    if (_spent > 0) _spent--;
  }

  void _rollIfNewDay([DateTime? now]) {
    if (now != null) _clockOverride = now.toUtc();
    final DateTime today = _dayOf((_clockOverride ?? DateTime.now()).toUtc());
    if (today != _window) {
      _window = today;
      _spent = 0;
    }
  }

  /// Serialised form for persistence.
  Map<String, Object> toJson() {
    _rollIfNewDay();
    return <String, Object>{
      'limit': dailyLimit,
      'spent': _spent,
      'window': _window.toIso8601String(),
    };
  }

  /// Restores a persisted budget, discarding the counters if the stored window
  /// is unparseable.
  static QuotaBudget fromJson(
    Map<String, Object> json, {
    required int fallbackLimit,
    DateTime? now,
  }) {
    final QuotaBudget budget = QuotaBudget(
      dailyLimit: json['limit'] as int? ?? fallbackLimit,
      now: now,
    );
    final Object? window = json['window'];
    final Object? spent = json['spent'];
    if (window is String && spent is int) {
      try {
        budget._window = DateTime.parse(window);
        budget._spent = spent;
      } on FormatException {
        budget._spent = 0;
      }
    }
    budget._rollIfNewDay(now);
    return budget;
  }
}
