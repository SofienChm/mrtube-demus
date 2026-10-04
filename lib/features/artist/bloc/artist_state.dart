part of 'artist_bloc.dart';

sealed class ArtistStatus extends Equatable {
  const ArtistStatus();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ArtistInitial extends ArtistStatus {
  const ArtistInitial();
}

final class ArtistLoading extends ArtistStatus {
  const ArtistLoading();
}

final class ArtistLoadingMore extends ArtistStatus {
  const ArtistLoadingMore();
}

final class ArtistSuccess extends ArtistStatus {
  const ArtistSuccess();
}

/// The artist exists but has published nothing streamable. A distinct state
/// from failure, because an empty channel is a fact about the artist, not an
/// error the user should retry.
final class ArtistEmpty extends ArtistStatus {
  const ArtistEmpty();
}

final class ArtistFailure extends ArtistStatus {
  const ArtistFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

final class ArtistState extends Equatable {
  const ArtistState({
    required this.artist,
    this.status = const ArtistInitial(),
    this.tracks = const <Track>[],
    this.nextPageToken,
    this.error,
  });

  final ArtistSummary artist;
  final ArtistStatus status;

  /// Accumulated across pages.
  final List<Track> tracks;

  final String? nextPageToken;

  /// Set when a *subsequent* page failed while earlier pages are still shown.
  final Failure? error;

  bool get hasMore => nextPageToken != null && nextPageToken!.isNotEmpty;

  bool get isBusy => status is ArtistLoading || status is ArtistLoadingMore;

  ArtistState copyWith({
    ArtistStatus? status,
    List<Track>? tracks,
    String? nextPageToken,
    Failure? error,
    bool clearPageToken = false,
    bool clearError = false,
  }) {
    return ArtistState(
      artist: artist,
      status: status ?? this.status,
      tracks: tracks ?? this.tracks,
      nextPageToken: clearPageToken
          ? null
          : (nextPageToken ?? this.nextPageToken),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    artist,
    status,
    tracks,
    nextPageToken,
    error,
  ];
}
