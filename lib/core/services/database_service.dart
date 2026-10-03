import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';

import '../models/playlist.dart';
import '../models/track.dart';

/// Local persistence, backed by Hive.
///
/// Boxes are opened as `Box<dynamic>` and every read funnels through the
/// [_asJson] guard, which both satisfies the loose generic and means a single
/// corrupt row can never take down a whole list. Values are strictly primitives
/// (String / int / bool / null), so no Hive type adapters or `build_runner`
/// codegen are needed.
///
/// All reads are synchronous. That is the whole point: the UI can call
/// [getTrack] or [getTracks] directly from `build` and never touch a Future,
/// which is what keeps scroll and first paint off the event loop's disk path.
final class DatabaseService {
  DatabaseService._(
    this._tracks,
    this._playlists,
    this._favorites,
    this._history,
    this._queryCache,
    this._settings,
  );

  static const String _tracksBox = 'tracks';
  static const String _playlistsBox = 'playlists';
  static const String _favoritesBox = 'favorites';
  static const String _historyBox = 'history';
  static const String _queryCacheBox = 'query_cache';
  static const String _settingsBox = 'settings';

  /// Cached search pages older than this are treated as stale.
  static const Duration queryTtl = Duration(hours: 12);

  /// Hard cap on cached search pages, evicted oldest-write-first.
  static const int _queryCacheLimit = 300;

  /// Hard cap on history rows.
  static const int _historyLimit = 500;

  final Box<dynamic> _tracks;
  final Box<dynamic> _playlists;
  final Box<String> _favorites;
  final Box<dynamic> _history;
  final Box<dynamic> _queryCache;
  final Box<dynamic> _settings;

  /// Production entry point. `Hive.initFlutter` resolves the documents
  /// directory through the `path_provider` platform channel.
  static Future<DatabaseService> init() async {
    await Hive.initFlutter();
    return _openBoxes();
  }

  /// Test entry point against an explicit directory, which avoids the
  /// platform channel and lets each test get an isolated store.
  @visibleForTesting
  static Future<DatabaseService> initAt(String path) async {
    Hive.init(path);
    return _openBoxes();
  }

  static Future<DatabaseService> _openBoxes() async {
    return DatabaseService._(
      await Hive.openBox<dynamic>(_tracksBox),
      await Hive.openBox<dynamic>(_playlistsBox),
      await Hive.openBox<String>(_favoritesBox),
      await Hive.openBox<dynamic>(_historyBox),
      await Hive.openBox<dynamic>(_queryCacheBox),
      await Hive.openBox<dynamic>(_settingsBox),
    );
  }

  /// Narrows an arbitrary boxed value to a JSON-shaped map, or null.
  static Map<String, dynamic>? _asJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> out = <String, dynamic>{};
    for (final MapEntry<dynamic, dynamic> e in raw.entries) {
      final Object? key = e.key;
      if (key is! String) return null;
      out[key] = e.value;
    }
    return out;
  }

  List<Box<dynamic>> get _allBoxes => <Box<dynamic>>[
    _tracks,
    _playlists,
    _history,
    _queryCache,
  ];

  // ---------------------------------------------------------------- tracks

  /// Synchronous read. Safe on the frame path because the box is already open.
  Track? getTrack(String id) {
    final Map<String, dynamic>? json = _asJson(_tracks.get(id));
    if (json == null) return null;
    try {
      return Track.fromJson(json);
    } on Object {
      return null;
    }
  }

  /// Synchronous multi-read for list construction. One pass, no futures, and a
  /// single try/catch for the whole batch.
  List<Track> getTracks(List<String> ids) {
    final List<Track> tracks = <Track>[];
    for (final String id in ids) {
      final Track? track = getTrack(id);
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  Future<void> putTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await _tracks.putAll(<dynamic, dynamic>{
      for (final Track t in tracks) t.id: t.toJson(),
    });
  }

  Future<void> putTrack(Track track) => putTracks(<Track>[track]);

  /// Drops tracks no longer referenced by a playlist or favorite.
  Future<int> evictOrphanTracks(Set<String> referencedIds) async {
    final List<dynamic> dead = <dynamic>[
      for (final dynamic key in _tracks.keys.toList(growable: false))
        if (!referencedIds.contains(key)) key,
    ];
    if (dead.isEmpty) return 0;
    await _tracks.deleteAll(dead);
    return dead.length;
  }

  // -------------------------------------------------------------- favorites

  Set<String> get favoriteIds => _favorites.values.toSet();

  bool isFavorite(String trackId) => _favorites.containsKey(trackId);

  Future<void> setFavorite(String trackId, bool value) async {
    if (value) {
      await _favorites.put(trackId, trackId);
    } else {
      await _favorites.delete(trackId);
    }
  }

  // --------------------------------------------------------------- history

  List<HistoryEntry> getHistory({int limit = 100}) {
    final List<HistoryEntry> entries = <HistoryEntry>[];
    for (final dynamic raw in _history.values) {
      final Map<String, dynamic>? json = _asJson(raw);
      if (json == null) continue;
      final Object? trackId = json['trackId'];
      final Object? playedAt = json['playedAt'];
      if (trackId is! String || playedAt is! String) continue;
      try {
        entries.add(
          HistoryEntry(
            trackId: trackId,
            playedAt: DateTime.parse(playedAt),
            completed: json['completed'] as bool? ?? false,
            playCount: json['playCount'] as int? ?? 1,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    entries.sort(
      (HistoryEntry a, HistoryEntry b) => b.playedAt.compareTo(a.playedAt),
    );
    return entries.take(limit).toList(growable: false);
  }

  Future<void> recordPlay(String trackId, {bool completed = false}) async {
    final Map<String, dynamic>? existing = _asJson(_history.get(trackId));
    await _history.put(trackId, <String, dynamic>{
      'trackId': trackId,
      'playedAt': DateTime.now().toIso8601String(),
      'completed': completed,
      'playCount': ((existing?['playCount'] as int?) ?? 0) + 1,
    });
    await _trimHistory();
  }

  Future<void> clearHistory() => _history.clear();

  Future<void> _trimHistory() async {
    final int excess = _history.length - _historyLimit;
    if (excess <= 0) return;
    await _history.deleteAll(_oldestHistoryKeys(excess));
  }

  List<dynamic> _oldestHistoryKeys(int count) {
    final List<MapEntry<dynamic, DateTime>> entries =
        <MapEntry<dynamic, DateTime>>[];
    for (final dynamic key in _history.keys.toList(growable: false)) {
      final Map<String, dynamic>? json = _asJson(_history.get(key));
      final Object? at = json?['playedAt'];
      if (at is String) {
        entries.add(MapEntry<dynamic, DateTime>(key, DateTime.parse(at)));
      }
    }
    entries.sort(
      (MapEntry<dynamic, DateTime> a, MapEntry<dynamic, DateTime> b) =>
          a.value.compareTo(b.value),
    );
    return entries
        .take(count)
        .map((MapEntry<dynamic, DateTime> e) => e.key)
        .toList();
  }

  // -------------------------------------------------------------- playlists

  List<Playlist> get playlists {
    final List<Playlist> result = <Playlist>[];
    for (final dynamic raw in _playlists.values) {
      final Map<String, dynamic>? json = _asJson(raw);
      if (json == null) continue;
      try {
        result.add(Playlist.fromJson(json));
      } on Object {
        continue;
      }
    }
    result.sort((Playlist a, Playlist b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Playlist? getPlaylist(String id) {
    final Map<String, dynamic>? json = _asJson(_playlists.get(id));
    if (json == null) return null;
    try {
      return Playlist.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> putPlaylist(Playlist playlist) =>
      _playlists.put(playlist.id, playlist.toJson());

  Future<void> deletePlaylist(String id) => _playlists.delete(id);

  // ----------------------------------------------------------- query cache

  String _pageKey(String query, int page) => '$page:$query';

  /// Returns a cached search page, or null when absent or past its TTL.
  TrackPage? cachedPage(String query, {int page = 0}) {
    final Map<String, dynamic>? json = _asJson(
      _queryCache.get(_pageKey(query, page)),
    );
    if (json == null) return null;

    final Object? at = json['at'];
    if (at is! String) return null;
    final DateTime cachedAt;
    try {
      cachedAt = DateTime.parse(at);
    } on FormatException {
      return null;
    }
    if (DateTime.now().difference(cachedAt) > queryTtl) {
      unawaited(_queryCache.delete(_pageKey(query, page)));
      return null;
    }

    final Object? items = json['items'];
    if (items is! List) return null;
    final List<Track> tracks = <Track>[];
    for (final Object? item in items) {
      final Map<String, dynamic>? trackJson = _asJson(item);
      if (trackJson == null) continue;
      try {
        tracks.add(Track.fromJson(trackJson));
      } on Object {
        continue;
      }
    }

    return TrackPage(
      items: tracks,
      nextPageToken: json['next'] as String?,
      totalEstimate: json['total'] as int?,
    );
  }

  Future<void> cachePage(
    String query,
    TrackPage page, {
    int pageIndex = 0,
  }) async {
    await _queryCache.put(_pageKey(query, pageIndex), <String, dynamic>{
      'at': DateTime.now().toIso8601String(),
      'items': page.items.map((Track t) => t.toJson()).toList(),
      'next': page.nextPageToken,
      'total': page.totalEstimate,
    });
    await _trimQueryCache();
  }

  Future<void> _trimQueryCache() async {
    final int excess = _queryCache.length - _queryCacheLimit;
    if (excess <= 0) return;

    // Hive has no access-time tracking, so the write timestamp recorded in the
    // row is the best available recency proxy. Evict oldest-write-first.
    final List<MapEntry<dynamic, DateTime>> entries =
        <MapEntry<dynamic, DateTime>>[];
    for (final dynamic key in _queryCache.keys.toList(growable: false)) {
      final Object? at = _asJson(_queryCache.get(key))?['at'];
      if (at is! String) continue;
      try {
        entries.add(MapEntry<dynamic, DateTime>(key, DateTime.parse(at)));
      } on FormatException {
        continue;
      }
    }
    entries.sort(
      (MapEntry<dynamic, DateTime> a, MapEntry<dynamic, DateTime> b) =>
          a.value.compareTo(b.value),
    );
    await _queryCache.deleteAll(
      entries
          .take(excess)
          .map((MapEntry<dynamic, DateTime> e) => e.key)
          .toList(),
    );
  }

  // --------------------------------------------------------------- settings

  T? setting<T>(String key) {
    final Object? value = _settings.get(key);
    return value is T ? value : null;
  }

  Future<void> setSetting(String key, Object value) =>
      _settings.put(key, value);

  // ------------------------------------------------------------------ admin

  /// Approximate on-disk footprint of the app's cache, for the settings screen.
  /// Stats each box's backing file rather than walking rows.
  Future<int> cacheSizeBytes() async {
    int total = 0;
    for (final Box<dynamic> box in <Box<dynamic>>[..._allBoxes, _settings]) {
      final String? path = box.path;
      if (path == null || path.isEmpty) continue;
      try {
        total += File(path).lengthSync();
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  /// Wipes cached metadata and orphaned tracks, preserving favorites,
  /// playlists and history.
  Future<int> clearMetadataCache() async {
    await _queryCache.clear();
    final Set<String> referenced = <String>{
      ...favoriteIds,
      for (final Playlist p in playlists) ...p.trackIds,
      for (final HistoryEntry h in getHistory(limit: _historyLimit)) h.trackId,
    };
    return evictOrphanTracks(referenced);
  }

  Future<void> close() => Hive.close();
}
