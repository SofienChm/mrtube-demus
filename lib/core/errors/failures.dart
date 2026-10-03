/// Domain-level error type. Blocs expose [Failure]s to the UI; infrastructure
/// throws typed `AppException`s which are translated at the repository
/// boundary.
///
/// Declared as a `sealed` hierarchy rather than an Equatable subclass because a
/// sealed class cannot also be mixed in; equality is therefore explicit.
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => '$runtimeType($message)';
}

/// Network layer failed: offline, DNS, timeout, 5xx.
final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Network unavailable. Check your connection.',
  ]);
}

/// Upstream provider returned a quota / rate-limit response.
final class RateLimitFailure extends Failure {
  const RateLimitFailure([
    super.message = 'Too many requests. Try again shortly.',
  ]);
}

/// Content is unavailable: removed, private, region-locked, or embed-disabled.
final class UnavailableContentFailure extends Failure {
  const UnavailableContentFailure([
    super.message = 'This track is not available for playback.',
  ]);
}

/// Audio pipeline rejected or dropped the source.
final class PlaybackFailure extends Failure {
  const PlaybackFailure([super.message = 'Playback failed.']);
}

/// Local persistence failed.
final class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Could not read local storage.']);
}

/// Caller cancelled the operation (e.g. query superseded by a newer keystroke).
final class CancelledFailure extends Failure {
  const CancelledFailure([super.message = 'Request cancelled.']);
}
