import 'package:equatable/equatable.dart';

/// A user-created, ordered collection of tracks.
final class Playlist extends Equatable {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    required this.updatedAt,
    this.coverUrl,
    this.pendingSync = false,
  });

  final String id;
  final String name;

  /// Ordered [Track.id] references. Tracks themselves live in the track cache so
  /// a playlist row stays small and cheap to sync.
  final List<String> trackIds;

  final String? coverUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when local state has diverged from the server and still needs pushing.
  final bool pendingSync;

  Playlist copyWith({
    String? name,
    List<String>? trackIds,
    String? coverUrl,
    DateTime? updatedAt,
    bool? pendingSync,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      coverUrl: coverUrl ?? this.coverUrl,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'coverUrl': coverUrl,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'pendingSync': pendingSync,
  };

  static Playlist fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    trackIds: (json['trackIds'] as List<dynamic>? ?? const <dynamic>[])
        .cast<String>(),
    coverUrl: json['coverUrl'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    pendingSync: json['pendingSync'] as bool? ?? false,
  );

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    trackIds,
    coverUrl,
    createdAt,
    updatedAt,
    pendingSync,
  ];
}

/// One entry in listening history, used for the "recently played" rail and as
/// the payload sent to the backend for cross-device sync.
final class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.trackId,
    required this.playedAt,
    this.completed = false,
    this.playCount = 1,
  });

  final String trackId;
  final DateTime playedAt;
  final bool completed;
  final int playCount;

  @override
  List<Object?> get props => <Object?>[trackId, playedAt, completed, playCount];
}
