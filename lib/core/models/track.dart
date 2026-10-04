import 'package:equatable/equatable.dart';

/// How a given provider exposes audio for a track. This is the single most
/// important discriminator in the app, because it determines whether background
/// audio and lock-screen controls are possible at all.
enum PlaybackCapability {
  /// Provider yields a direct audio URL that `just_audio` can stream. Supports
  /// background playback, lock-screen transport, and offline caching.
  directAudio,

  /// Provider only permits playback through its official embedded player
  /// (webview). Audio stops when the app is backgrounded.
  embedOnly,
}

/// A single catalog entry.
///
/// Immutable and Equatable so BLoC states compare by value and skip rebuilds.
final class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.sourceId,
    required this.thumbnailUrl,
    this.album,
    this.duration,
    this.playbackCapability = PlaybackCapability.directAudio,
    this.streamUrl,
    this.playCount = 0,
    this.favoriteCount = 0,
    this.createdAt,
    this.userId,
  });

  /// Stable composite key: `<source>:<sourceId>`. Prevents collisions between
  /// providers that happen to use the same id space.
  final String id;

  final String title;
  final String artist;
  final String? album;
  final String sourceId;

  /// Highest-resolution thumbnail the provider advertises.
  final String? thumbnailUrl;

  final Duration? duration;

  final PlaybackCapability playbackCapability;

  /// Direct audio URL. Non-null only when [playbackCapability] is
  /// [PlaybackCapability.directAudio]. Resolved lazily, then cached.
  final String? streamUrl;

  /// Provider-reported play count. Used to order results by popularity, since
  /// provider relevance alone tends to surface keyword-stuffed titles over the
  /// artist the user actually typed.
  final int playCount;

  final int favoriteCount;

  /// Publication date, used to surface an artist's newest release.
  final DateTime? createdAt;

  /// Provider id of the uploading user. This is the only stable link from a
  /// track back to its artist, because artist *names* are neither unique nor
  /// stable: two different users can both be called "Samara", and one user can
  /// change their display name. Null for providers with no user concept.
  final String? userId;

  bool get isDirectAudio =>
      playbackCapability == PlaybackCapability.directAudio;

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? thumbnailUrl,
    Duration? duration,
    PlaybackCapability? playbackCapability,
    String? streamUrl,
    int? playCount,
    int? favoriteCount,
    DateTime? createdAt,
    String? userId,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      sourceId: sourceId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      playbackCapability: playbackCapability ?? this.playbackCapability,
      streamUrl: streamUrl ?? this.streamUrl,
      playCount: playCount ?? this.playCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'sourceId': sourceId,
    'thumbnailUrl': thumbnailUrl,
    'durationMs': duration?.inMilliseconds,
    'playbackCapability': playbackCapability.name,
    'streamUrl': streamUrl,
    'playCount': playCount,
    'favoriteCount': favoriteCount,
    'createdAt': createdAt?.toIso8601String(),
    'userId': userId,
  };

  static Track fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Unknown',
    artist: json['artist'] as String? ?? 'Unknown',
    album: json['album'] as String?,
    sourceId: json['sourceId'] as String? ?? '',
    thumbnailUrl: json['thumbnailUrl'] as String?,
    duration: json['durationMs'] == null
        ? null
        : Duration(milliseconds: json['durationMs'] as int),
    playbackCapability: PlaybackCapability.values.firstWhere(
      (PlaybackCapability c) => c.name == json['playbackCapability'],
      orElse: () => PlaybackCapability.embedOnly,
    ),
    streamUrl: json['streamUrl'] as String?,
    // Rows cached before these fields existed simply report zero, which sorts
    // last rather than throwing.
    playCount: json['playCount'] as int? ?? 0,
    favoriteCount: json['favoriteCount'] as int? ?? 0,
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.tryParse(json['createdAt'] as String),
    // Rows cached before this field existed simply have no channel link.
    userId: json['userId'] as String?,
  );

  @override
  List<Object?> get props => <Object?>[
    id,
    title,
    artist,
    album,
    sourceId,
    thumbnailUrl,
    duration,
    playbackCapability,
    streamUrl,
    playCount,
    favoriteCount,
    createdAt,
    userId,
  ];
}

/// A page of results plus the cursor needed to fetch the next one.
final class TrackPage extends Equatable {
  const TrackPage({
    required this.items,
    required this.nextPageToken,
    this.totalEstimate,
  });

  final List<Track> items;
  final String? nextPageToken;
  final int? totalEstimate;

  bool get hasMore => nextPageToken != null && nextPageToken!.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[items, nextPageToken, totalEstimate];
}
