import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../errors/exceptions.dart';
import '../models/track.dart';
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
final class AudiusMusicSource implements MusicSource {
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

  @override
  void dispose() => _dio.close(force: true);
}
