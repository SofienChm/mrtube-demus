import 'package:dio/dio.dart';

import '../errors/exceptions.dart';
import '../models/track.dart';
import '../utils/quota_budget.dart';
import 'music_source.dart';
import 'track_repository.dart' show DurationHydratable;

/// YouTube metadata + playback via the **official** APIs only.
///
/// - Metadata: YouTube Data API v3 (`search.list` + `videos.list`).
/// - Playback: the official IFrame Player API, surfaced by
///   `youtube_player_iframe`.
///
/// No stream extraction is performed, so tracks come back as
/// [PlaybackCapability.embedOnly] and background audio is unavailable for them.
/// See [searchBudget] for the hard constraint that shapes this whole class.
final class YouTubeMusicSource implements MusicSource, DurationHydratable {
  YouTubeMusicSource({required this.apiKey, Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      headers: const <String, String>{'Accept': 'application/json'},
    );
  }

  /// Google's default allowance for `search.list`: 100 calls/day, shared by
  /// every user of the project. There is no way to raise it without a billing
  /// appeal, and it is the binding constraint on this provider.
  static const int searchCallsPerDay = 100;

  static const String _host = 'https://www.googleapis.com/youtube/v3';

  final String apiKey;
  final Dio _dio;

  QuotaBudget? _budget;

  /// Shared budget so every screen draws from one daily pool. Attach once
  /// during boot with a restored or fresh budget.
  QuotaBudget get searchBudget =>
      _budget ??= QuotaBudget(dailyLimit: searchCallsPerDay);

  @override
  String get id => 'youtube';

  @override
  bool get supportsDirectAudio => false;

  @override
  bool get searchIsQuotaBound => true;

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

    // Spend from the shared daily pool before touching the network. Exceeding
    // it yields 403s that look like outages to every user simultaneously, which
    // is exactly what we are avoiding.
    if (!searchBudget.tryConsume()) {
      throw const QuotaExceededException(
        'Daily search limit reached. Showing cached results.',
      );
    }

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_host/search',
        queryParameters: <String, dynamic>{
          'part': 'snippet',
          'type': 'video',
          'q': trimmed,
          'maxResults': 25,
          'videoCategoryId': '10', // Music
          'safeSearch': 'moderate',
          'pageToken': ?pageToken,
          'key': apiKey,
        },
      );
      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );

      final Object? rawItems = body['items'];
      if (rawItems is! List) {
        return const TrackPage(items: <Track>[], nextPageToken: null);
      }

      final List<Track> tracks = <Track>[];
      for (final Object? item in rawItems) {
        if (item is! Map) continue;
        final Track? track = _parseSearchItem(Map<String, dynamic>.from(item));
        if (track != null) tracks.add(track);
      }

      final Object? pageInfo = body['pageInfo'];
      final String? next = pageInfo is Map
          ? (pageInfo['nextPageToken'] as String?)
          : null;

      return TrackPage(
        items: tracks,
        nextPageToken: next,
        totalEstimate: pageInfo is Map
            ? (pageInfo['totalResults'] as int?)
            : null,
      );
    } on DioException catch (error) {
      final AppException classified = classifyDioError(error);
      // A transport fault never reached the provider, so the unit is refunded.
      // A 4xx was really served and is billed, so it stays spent.
      if (classified is TransportException) searchBudget.refund();
      throw classified;
    }
  }

  Track? _parseSearchItem(Map<String, dynamic> item) {
    final Object? idNode = item['id'];
    final Object? videoId = idNode is Map ? idNode['videoId'] : null;
    if (videoId is! String || videoId.isEmpty) return null;

    final Object? snippetNode = item['snippet'];
    if (snippetNode is! Map) return null;
    final Map<String, dynamic> snippet = Map<String, dynamic>.from(snippetNode);

    final Object? titleNode = snippet['title'];
    final String title = titleNode is String && titleNode.isNotEmpty
        ? titleNode
        : 'Unknown';

    final Object? channelNode = snippet['channelTitle'];
    final String artist = channelNode is String ? channelNode : 'Unknown';

    return Track(
      id: 'youtube:$videoId',
      sourceId: videoId,
      title: title,
      artist: artist,
      thumbnailUrl: _bestThumbnail(snippet['thumbnails']),
      playbackCapability: PlaybackCapability.embedOnly,
    );
  }

  /// `search.list` returns no duration; `videos.list` costs only 1 unit, so it
  /// is cheap enrichment and worth doing for a page of results. Failures are
  /// swallowed because a missing duration must never block playback.
  @override
  Future<List<Track>> hydrate(List<Track> tracks) async {
    if (tracks.isEmpty) return tracks;
    final List<String> ids = <String>[for (final Track t in tracks) t.sourceId];

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_host/videos',
        queryParameters: <String, dynamic>{
          'part': 'contentDetails',
          'id': ids.join(','),
          'key': apiKey,
        },
      );
      final Map<String, dynamic> body = Map<String, dynamic>.from(
        response.data as Map<dynamic, dynamic>,
      );
      final Object? rawItems = body['items'];
      if (rawItems is! List) return tracks;

      final Map<String, Duration> durations = <String, Duration>{};
      for (final Object? item in rawItems) {
        if (item is! Map) continue;
        final Map<String, dynamic> row = Map<String, dynamic>.from(item);
        final Object? vid = row['id'];
        final Object? details = row['contentDetails'];
        if (vid is! String || details is! Map) continue;
        final Object? iso = details['duration'];
        if (iso is! String) continue;
        final Duration? parsed = _parseIso8601Duration(iso);
        if (parsed != null) durations[vid] = parsed;
      }

      return <Track>[
        for (final Track t in tracks)
          if (durations.containsKey(t.sourceId))
            t.copyWith(duration: durations[t.sourceId])
          else
            t,
      ];
    } on DioException {
      return tracks;
    }
  }

  @override
  Future<Track> resolve(Track track) async {
    // Nothing to resolve: playback goes through the official embed player, so
    // there is no URL to fetch and no signature to mint.
    return track;
  }

  static String? _bestThumbnail(Object? node) {
    if (node is! Map) return null;
    String? best;
    int bestWidth = -1;
    for (final MapEntry<dynamic, dynamic> entry in node.entries) {
      final Object? value = entry.value;
      if (value is! Map) continue;
      final Object? url = value['url'];
      final Object? width = value['width'];
      if (url is! String) continue;
      final int w = width is int ? width : 0;
      if (w > bestWidth) {
        bestWidth = w;
        best = url;
      }
    }
    return best;
  }

  /// Parses the ISO-8601 subset YouTube returns (`PT1H2M3S`, `PT4M13S`).
  static Duration? _parseIso8601Duration(String value) {
    final RegExpMatch? match = RegExp(
      r'^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final int days = int.tryParse(match.group(1) ?? '') ?? 0;
    final int hours = int.tryParse(match.group(2) ?? '') ?? 0;
    final int minutes = int.tryParse(match.group(3) ?? '') ?? 0;
    final int seconds = int.tryParse(match.group(4) ?? '') ?? 0;
    return Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

  @override
  void dispose() => _dio.close(force: true);
}
