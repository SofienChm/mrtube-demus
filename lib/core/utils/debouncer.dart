import 'dart:async';

/// Collapses a burst of calls into a single trailing invocation.
///
/// Used for the search field so we issue at most one upstream request per
/// pause in typing, and for scroll-driven prefetch so a fast fling does not
/// enqueue dozens of resolutions.
final class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  bool get isPending => _timer?.isActive ?? false;

  /// Runs [action] after [duration] of quiet. Any pending call is cancelled.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Runs [action] immediately, cancelling anything pending.
  void runNow(void Function() action) {
    _timer?.cancel();
    _timer = null;
    action();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}

/// Trailing-edge debounce that keeps the result only if it is still the newest.
///
/// Guards the classic race where a slow request for "da" resolves after a fast
/// request for "dark" and clobbers the newer state.
final class DebouncedAsync<T> {
  DebouncedAsync(this.duration);

  final Duration duration;
  Timer? _timer;
  int _generation = 0;

  /// Returns `null` if this invocation was superseded before it completed.
  Future<T?> run(Future<T> Function() action) async {
    final int generation = ++_generation;
    _timer?.cancel();

    final Completer<T?> completer = Completer<T?>();
    _timer = Timer(duration, () async {
      try {
        final T result = await action();
        if (generation == _generation) {
          completer.complete(result);
        } else {
          completer.complete();
        }
      } on Object catch (error, stackTrace) {
        if (generation == _generation) {
          completer.completeError(error, stackTrace);
        } else {
          completer.complete();
        }
      }
    });

    return completer.future;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
