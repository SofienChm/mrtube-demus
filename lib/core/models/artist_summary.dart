import 'package:equatable/equatable.dart';

/// An artist/channel as the provider knows them.
///
/// This exists separately from [Track] because an artist is a first-class thing
/// a listener searches for. Track search answers "which song matches these
/// words"; it cannot answer "who is this person", because a provider's track
/// relevance is keyword-driven and will happily return a song merely titled
/// after the artist being searched for.
final class ArtistSummary extends Equatable {
  const ArtistSummary({
    required this.id,
    required this.name,
    required this.sourceId,
    this.handle,
    this.avatarUrl,
    this.coverUrl,
    this.followerCount = 0,
    this.trackCount = 0,
    this.isVerified = false,
    this.bio,
    this.location,
  });

  /// Composite key: `<source>:<sourceId>`.
  final String id;

  final String name;

  /// Provider-native id, used to fetch this artist's full track list.
  final String sourceId;

  /// `@handle`, which is the closest thing the platform has to a stable,
  /// human-typeable channel address.
  final String? handle;

  final String? avatarUrl;
  final String? coverUrl;
  final int followerCount;
  final int trackCount;
  final bool isVerified;
  final String? bio;
  final String? location;

  /// Display form of the channel address, e.g. `@jmar_`.
  String get handleLabel => handle == null || handle!.isEmpty ? '' : '@$handle';

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    sourceId,
    handle,
    avatarUrl,
    coverUrl,
    followerCount,
    trackCount,
    isVerified,
    bio,
    location,
  ];
}
