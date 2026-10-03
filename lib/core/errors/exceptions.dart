import 'package:dio/dio.dart';

import 'failures.dart';

/// Infrastructure-level exception. Repositories catch these and rethrow the
/// matching [Failure] so that blocs never see a transport-layer type.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// Wraps any [DioException], classifying connectivity vs. rate-limit vs. HTTP.
final class TransportException extends AppException {
  const TransportException(super.message, {super.cause});
}

/// Upstream signalled quota exhaustion (HTTP 403 with `quotaExceeded`, or 429).
final class QuotaExceededException extends AppException {
  const QuotaExceededException(super.message, {super.cause});
}

/// Content cannot be resolved for playback (private, removed, embed disabled).
final class ContentUnavailableException extends AppException {
  const ContentUnavailableException(super.message, {super.cause});
}

/// Translates a raw [DioException] into the appropriate typed exception.
AppException classifyDioError(DioException error) {
  final int? status = error.response?.statusCode;
  final String body = error.response?.data is String
      ? error.response!.data as String
      : '';

  final bool quotaHit =
      status == 429 ||
      (status == 403 && body.contains('quotaExceeded')) ||
      (status == 403 && body.contains('rateLimitExceeded')) ||
      (status == 403 && body.contains('userRateLimitExceeded'));

  if (quotaHit) {
    return QuotaExceededException('Provider quota exhausted.', cause: error);
  }

  if (status == 404 || status == 410) {
    return const ContentUnavailableException('Content no longer exists.');
  }

  if (status != null && status >= 400 && status < 500) {
    return TransportException(
      'Request rejected by provider (HTTP $status).',
      cause: error,
    );
  }

  return TransportException(
    'Could not reach the content provider.',
    cause: error,
  );
}

/// Maps a typed [AppException] to the domain [Failure] the UI should render.
Failure toFailure(AppException error) => switch (error) {
  QuotaExceededException() => const RateLimitFailure(),
  ContentUnavailableException() => const UnavailableContentFailure(),
  TransportException() => const NetworkFailure(),
};
