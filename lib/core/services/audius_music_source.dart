import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../errors/exceptions.dart';
import '../models/artist_summary.dart';
import '../models/track.dart';
import 'artist_source.dart';
import 'music_source.dart';

/// Audius: direct-audio playback with no daily quota cliff.
///
/// Audius is a decentralised music platform built for exactly this use case.
/// Unlike a scraped provider it serves first-party, public CDN URLs for every
/// streamable track, which means:
///
/// * `just_audio` gets a real URL, so background playback, lock-screen
///   controls, CarPlay, and seeking all work.
/// * There is no 100-calls/day project-wide allowance to exhaust. Rate limits
///   are per-client and an order of magnitude higher.
///
/// Endpoint behaviour was verified against the live API rather than assumed:
///
/// * `GET /v1/tracks/search` returns `{ "data": [...] }` with **no** pagination
///   metadata; `cursor` is ignored. `limit` + `offset` do work, so paging is
///   offset-based.
/// * `stream` is an **object** (`{ url, mirrors }`), not a path string, and
///   `url` is already absolute.
/// * Playability is per-track via `is_streamable` / `is_available` /
///   `is_stream_gated` / `is_delete`.
final class AudiusMusicSource implements MusicSource, ArtistSource {
  AudiusMusicSource({this.appName = 'mrplay', Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      headers: const <String, String>{'Accept': 'application/json'},
    );
  }

  /// Audius rejects unidentified clients. This doubles as the rate-limit key, so
  /// it should identify the app rather than a specific user.
  static const String defaultAppName = 'mrplay';

  static const String _host = 'https://discoveryprovider.audius.co';

  /// Results per page. Kept at 25 to match the page-size assumption in
  /// `SearchBloc._pageIndexFor`.
  static const int pageSize = 25;

  /// Comfortably under the API's maximum and large enough that most queries
  /// finish on the first page.
  static const int _maxResults = 50;

  final String appName;
  final Dio _dio;

  @override
  String get id => 'audius';

  @override
  bool get supportsDirectAudio => true;

  @override
  bool get searchIsQuotaBound => false;

  @override
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const TrackPage(items: <Track>[], nextPageToken: null);
    }

    // Offset paging: the token is simply the next offset as a string, which
    // keeps it compatible with the `String? nextPageToken` the rest of the app
    // already passes around.
    final int offset = pageToken != null
        ? (int.tryParse(pageToken) ?? pageIndex * pageSize)
        : pageIndex * pageSize;

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_host/v1/tracks/search',
        queryParameters: <String, dynamic>{
          'query': trimmed,
          'app_name': appName,
          'limit': _maxResults,
          'offset': offset,
        },
      );

      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      final Object? rawItems = body['data'];
      if (rawItems is! List) {
        return const TrackPage(items: <Track>[], nextPageToken: null);
      }

      final List<Track> tracks = <Track>[];
      for (final Object? item in rawItems) {
        if (item is! Map) continue;
        final Track? track = _parseTrack(Map<String, dynamic>.from(item));
        // Unplayable tracks are dropped here rather than surfaced and failed on
        // tap, which is a worse experience than a shorter list.
        if (track != null) tracks.add(track);
      }

      // Offset paging cannot know whether more results exist, so infer it from a
      // full page. A short page is the end.
      final int nextOffset = offset + _maxResults;
      final String? next = tracks.length < _maxResults
          ? null
          : nextOffset.toString();

      return TrackPage(items: tracks, nextPageToken: next, totalEstimate: null);
    } on DioException catch (error) {
      throw classifyDioError(error);
    }
  }

  @override
  Future<Track> resolve(Track track) async {
    // Already playable from the search payload, so the cache usually answers
    // this without a request. The fallback fetch covers a cold cache or a track
    // that was only ever seen as a bare id.
    final String? existing = track.streamUrl;
    if (existing != null && track.isDirectAudio) return track;

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_host/v1/tracks/${track.sourceId}',
        queryParameters: <String, dynamic>{'app_name': appName},
      );
      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      final Track? resolved = _parseTrack(body);
      if (resolved == null) {
        throw const ContentUnavailableException(
          'This track is no longer available.',
        );
      }
      return resolved;
    } on DioException catch (error) {
      throw classifyDioError(error);
    }
  }

  /// Audius returns numbers as int, double, or numeric string depending on the
  /// endpoint, so normalise rather than assume.
  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Maps one API track object to a [Track], or null when it cannot be played.
  @visibleForTesting
  static Track? parseTrackPayload(Map<String, dynamic> json) =>
      _parseTrack(json);

  static Track? _parseTrack(Map<String, dynamic> json) {
    final Object? sourceId = json['id'];
    if (sourceId is! String || sourceId.isEmpty) return null;

    // Unavailable / deleted / gated tracks have no public stream. Gated tracks
    // in particular need an owner-signed URL we deliberately do not obtain.
    if (json['is_delete'] == true) return null;
    if (json['is_available'] == false) return null;
    if (json['is_stream_gated'] == true) return null;
    if (json['is_streamable'] == false) return null;

    final String? streamUrl = _streamUrl(json['stream']);
    // Without a URL this cannot back direct audio, so it is filtered out rather
    // than offered and then failed at tap time.
    if (streamUrl == null) return null;

    final Object? userNode = json['user'];
    final Map<String, dynamic> user = userNode is Map
        ? Map<String, dynamic>.from(userNode)
        : const <String, dynamic>{};

    final Object? titleNode = json['title'];
    final String title = titleNode is String && titleNode.trim().isNotEmpty
        ? titleNode.trim()
        : 'Unknown';

    final Object? artistNode = user['name'];
    final String artist = artistNode is String && artistNode.trim().isNotEmpty
        ? artistNode.trim()
        : 'Unknown artist';

    final Object? albumNode = json['album'];

    return Track(
      id: 'audius:$sourceId',
      sourceId: sourceId,
      title: title,
      artist: artist,
      album: albumNode is String && albumNode.isNotEmpty ? albumNode : null,
      thumbnailUrl: _artworkUrl(json['artwork']),
      duration: _durationSeconds(json['duration']),
      playbackCapability: PlaybackCapability.directAudio,
      streamUrl: streamUrl,
      // Popularity and recency drive result ordering; without them every track
      // from an artist looks equally relevant.
      playCount: _asInt(json['play_count']),
      favoriteCount: _asInt(json['favorite_count']),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      // `user.id` rather than the track's own `user_id`: inside a track payload
      // that field holds the CID form, and the CID is what a user-search result
      // can be joined against.
      userId: _userIdOf(user),
    );
  }

  /// `stream` is `{ "url": ..., "mirrors": [...] }`. Older shapes used a bare
  /// path string, so both are accepted.
  static String? _streamUrl(Object? node) {
    if (node is String) return node.isEmpty ? null : node;
    if (node is! Map) return null;

    final Object? url = node['url'];
    if (url is String && url.isNotEmpty) return url;
    return null;
  }

  /// Prefers a mid-size cover: large enough for the full-screen player, small
  /// enough not to dominate a list row's memory budget.
  static String? _artworkUrl(Object? node) {
    if (node is String) return node.isEmpty ? null : node;
    if (node is! Map) return null;

    for (final String size in const <String>[
      '480x480',
      '1000x1000',
      '150x150',
    ]) {
      final Object? url = node[size];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  /// `duration` is fractional seconds, but tolerate ints and junk.
  static Duration? _durationSeconds(Object? node) {
    if (node is! num) return null;
    if (node <= 0) return null;
    return Duration(milliseconds: (node * 1000).round());
  }

  /// Searches artist/channel accounts.
  ///
  /// Endpoint behaviour verified against the live API:
  ///
  /// * `GET /v1/users/search` returns `{ "data": [...] }` with no pagination
  ///   metadata, at most ~10 results, and ignores `cursor`.
  /// * The follower field is `follower_count` (singular). The plural
  ///   `followers_count` exists in the payload but is always `null`, so reading
  ///   the plural silently reports every artist as having zero followers.
  /// * Relevance is poor enough to require [ArtistUserRanker]: an exact name
  ///   query returned an unrelated 87k-follower account as the top result.
  ///
  /// Not part of [MusicSource] because it is a catalogue-shaped lookup rather
  /// than track playback, and only providers with real user accounts implement
  /// it.
  @override
  Future<List<ArtistSummary>> searchUsers(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <ArtistSummary>[];

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_host/v1/users/search',
        queryParameters: <String, dynamic>{
          'query': trimmed,
          'app_name': appName,
        },
      );

      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      final Object? rawItems = body['data'];
      if (rawItems is! List) return const <ArtistSummary>[];

      final List<ArtistSummary> artists = <ArtistSummary>[];
      for (final Object? item in rawItems) {
        if (item is! Map) continue;
        final ArtistSummary? artist = parseArtistPayload(
          Map<String, dynamic>.from(item),
        );
        if (artist != null) artists.add(artist);
      }
      return artists;
    } on DioException catch (error) {
      throw classifyDioError(error);
    }
  }

  /// Fetches one artist's tracks, newest first as the API orders them.
  ///
  /// `GET /v1/users/{id}/tracks` returns `{ "data": [...] }` with the same track
  /// shape as search and no pagination metadata, so paging is offset-based and
  /// the end is inferred from a short page.
  ///
  /// [artistId] accepts either the CID (`id`) or the numeric `user_id`; both
  /// resolve to the same account.
  @override
  Future<TrackPage> fetchArtistTracks(
    String artistId, {
    String? pageToken,
  }) async {
    final int offset = int.tryParse(pageToken ?? '') ?? 0;

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_host/v1/users/$artistId/tracks',
        queryParameters: <String, dynamic>{
          'app_name': appName,
          'limit': pageSize,
          'offset': offset,
        },
      );

      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      final Object? rawItems = body['data'];
      if (rawItems is! List) {
        return const TrackPage(items: <Track>[], nextPageToken: null);
      }

      final List<Track> tracks = <Track>[];
      for (final Object? item in rawItems) {
        if (item is! Map) continue;
        final Track? track = _parseTrack(Map<String, dynamic>.from(item));
        if (track != null) tracks.add(track);
      }

      final String? next = tracks.length < pageSize
          ? null
          : (offset + pageSize).toString();

      return TrackPage(items: tracks, nextPageToken: next);
    } on DioException catch (error) {
      throw classifyDioError(error);
    }
  }

  @visibleForTesting
  static ArtistSummary? parseArtistPayload(Map<String, dynamic> json) {
    final Object? sourceId = json['id'];
    if (sourceId is! String || sourceId.isEmpty) return null;

    final Object? nameNode = json['name'];
    final String name = nameNode is String && nameNode.trim().isNotEmpty
        ? nameNode.trim()
        : 'Unknown artist';

    final Object? handleNode = json['handle'];
    final Object? bioNode = json['bio'];
    final Object? locationNode = json['location'];

    return ArtistSummary(
      id: 'audius:$sourceId',
      sourceId: sourceId,
      name: name,
      handle: handleNode is String && handleNode.isNotEmpty ? handleNode : null,
      avatarUrl: _artworkUrl(json['profile_picture']),
      coverUrl: _coverUrl(json['cover_photo']),
      followerCount: _asInt(json['follower_count']),
      trackCount: _asInt(json['track_count']),
      isVerified: json['is_verified'] == true,
      bio:
          bioNode is String &&
              bioNode.trim().isNotEmpty &&
              bioNode.trim() != '-'
          ? bioNode.trim()
          : null,
      location: locationNode is String && locationNode.isNotEmpty
          ? locationNode
          : null,
    );
  }

  /// Cover photos are keyed by width alone (`"2000x"`), unlike track artwork
  /// which uses explicit dimensions.
  static String? _coverUrl(Object? node) {
    if (node is String) return node.isEmpty ? null : node;
    if (node is! Map) return null;

    final List<String> sizes = node.keys.map((dynamic k) => '$k').toList()
      ..sort((String a, String b) => _sizeOf(b).compareTo(_sizeOf(a)));
    for (final String size in sizes) {
      final Object? url = node[size];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  static int _sizeOf(String size) => int.tryParse(size.split('x').first) ?? 0;

  /// Both `id` (CID) and `user_id` (numeric) identify the same account and both
  /// are accepted by `/v1/users/{id}/tracks`, so prefer the CID for consistency
  /// with the id carried inside track payloads.
  static String? _userIdOf(Map<String, dynamic> user) {
    for (final String key in const <String>['id', 'user_id']) {
      final Object? value = user[key];
      if (value is String && value.isNotEmpty) return value;
      if (value is int) return value.toString();
    }
    return null;
  }

  @override
  void dispose() => _dio.close(force: true);
}
