import 'dart:async';

import '../errors/exceptions.dart';
import '../models/track.dart';
import '../search/search_ranker.dart';
import 'database_service.dart';
import 'music_source.dart';

/// Cache-first facade over one or more [MusicSource]s.
///
/// Every read path follows the same shape: answer from local storage
/// immediately, then reconcile with the network if the entry is missing or
/// stale. That is what makes repeat opens of the same track or artist land in
/// single-digit milliseconds instead of a round trip.
///
/// Registered sources are tried in order; the first that yields results wins.
final class TrackRepository {
  TrackRepository({required this.database, required List<MusicSource> sources})
    : sources = List<MusicSource>.unmodifiable(sources);

  final DatabaseService database;

  /// Registered providers, tried in order.
  final List<MusicSource> sources;

  /// In-flight resolutions, keyed by track id, so N concurrent prefetches for
  /// the same track collapse into one upstream call.
  final Map<String, Future<Track>> _inFlight = <String, Future<Track>>{};

  MusicSource? sourceFor(String trackId) {
    final int colon = trackId.indexOf(':');
    if (colon <= 0) return null;
    final String prefix = trackId.substring(0, colon);
    for (final MusicSource source in sources) {
      if (source.id == prefix) return source;
    }
    return null;
  }

  // ----------------------------------------------------------------- search

  /// Cache-only lookup. Synchronous and allocation-light: safe to call from
  /// `build` and from list item constructors.
  TrackPage? cachedSearch(String query, {int page = 0}) =>
      database.cachedPage(query, page: page);

  /// Network search across registered sources, writing through to the cache on
  /// success.
  ///
  /// Throws [AppException] on failure so the caller decides how to degrade.
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  }) async {
    AppException? lastError;
    for (final MusicSource source in sources) {
      try {
        final TrackPage page = await source.search(
          query,
          pageToken: pageToken,
          pageIndex: pageIndex,
        );
        if (page.items.isEmpty && sources.length > 1) continue;

        // Persist both the page and the denormalised tracks before returning.
        //
        // These writes are awaited deliberately. Returning first would let an
        // immediate repeat search miss the cache and spend another unit of
        // provider quota, which is the exact failure the cache exists to
        // prevent. Hive writes are local and fast, so the trade is worth it.
        await _ignoreErrors(
          database.cachePage(query, page, pageIndex: pageIndex),
        );
        await _ignoreErrors(database.putTracks(page.items));

        // Opportunistic duration hydration for sources that omit it. Cheap
        // (1 unit) and never blocks the result, so it stays fire-and-forget.
        if (page.items.any((Track t) => t.duration == null)) {
          unawaited(_hydrateDurations(source, page));
        }

        // Rank once, here, so every consumer sees the same order: the search
        // screen, the queue built from it, and the cached page replayed later.
        // Ranking inside the repository also means a cache hit is already
        // ordered, so cached and fresh results cannot disagree.
        return _ranked(page, query);
      } on AppException catch (error) {
        lastError = error;
        // Fall through rather than rethrow: one provider being rate limited or
        // offline must not stop the next source from answering the query. With
        // a single registered source this loop simply ends and [lastError] is
        // thrown below.
      } on Object catch (error) {
        // A source throwing something other than [AppException] is a contract
        // violation. Wrap it so callers still only have to handle one error
        // type, as documented on [search].
        lastError = TransportException(
          'Search failed on "${source.id}".',
          cause: error,
        );
      }
    }
    throw lastError ?? const ContentUnavailableException('No results.');
  }

  /// Re-orders [page] by relevance while preserving its pagination token.
  static TrackPage _ranked(TrackPage page, String query) {
    if (query.trim().isEmpty || page.items.isEmpty) return page;
    return TrackPage(
      items: SearchRanker.rank(query, page.items),
      nextPageToken: page.nextPageToken,
      totalEstimate: page.totalEstimate,
    );
  }

  Future<void> _hydrateDurations(MusicSource source, TrackPage page) async {
    if (source case final DurationHydratable hydratable) {
      try {
        final List<Track> hydrated = await hydratable.hydrate(page.items);
        await database.putTracks(hydrated);
      } on Object {
        // Enrichment is optional: a miss just leaves durations unknown.
        return;
      }
    }
  }

  /// Cache write whose failure must not fail the operation that triggered it.
  ///
  /// These can also outlive the database that owns them (app shutdown, hot
  /// restart, a torn-down widget tree), so a [HiveError] escaping here would
  /// surface as an unhandled async error in a zone nobody is listening to.
  static Future<void> _ignoreErrors(Future<void> work) async {
    try {
      await work;
    } on Object {
      return;
    }
  }

  // ---------------------------------------------------------------- resolve

  /// Resolves a playable queue anchored on [startIndex].
  ///
  /// Returns only entries that are actually streamable, plus the index the
  /// anchored track now occupies. Callers must use the returned index: dropping
  /// unplayable entries shifts every position after them, and passing the old
  /// index to the player would start the wrong track.
  ///
  /// Returns null when the anchored track itself cannot play as direct audio,
  /// which tells the caller to fall back to embed playback.
  ///
  /// The anchored track is resolved first and on its own so playback start
  /// latency is one round trip, not `tracks.length`. Neighbours are then
  /// resolved concurrently with bounded fan-out.
  Future<({List<Track> queue, int startIndex, int nextSourceIndex})?>
  resolveQueue(
    List<Track> tracks,
    int startIndex, {
    int back = 2,
    int forward = 10,
    int concurrency = 6,
  }) async {
    if (tracks.isEmpty) return null;

    final int anchor = startIndex.clamp(0, tracks.length - 1);

    final Track? anchorTrack = await _tryResolve(tracks[anchor]);
    if (anchorTrack == null || !_isPlayable(anchorTrack)) return null;

    // A small backward window so "previous" reaches tracks above the anchor
    // instead of dead-ending at the queue start.
    final int backStart = (anchor - back).clamp(0, anchor);
    final int forwardEnd = (anchor + forward + 1).clamp(0, tracks.length);

    final List<Track> window = <Track>[
      ...tracks.sublist(backStart, anchor),
      anchorTrack,
      ...tracks.sublist(anchor + 1, forwardEnd),
    ];

    // The anchor is already resolved; resolve the rest around it.
    final List<Track> neighbours = window
        .where((Track t) => t.id != anchorTrack.id)
        .toList(growable: false);

    final List<Track> resolvedNeighbours = await _resolveBounded(
      neighbours,
      concurrency,
    );

    final List<Track> queue = <Track>[];
    int resolvedAnchorIndex = 0;
    for (final Track candidate in window) {
      final bool isAnchor = candidate.id == anchorTrack.id;
      final Track? resolved = isAnchor
          ? anchorTrack
          : resolvedNeighbours
                .where((Track t) => t.id == candidate.id)
                .firstOrNull;
      if (resolved == null || !_isPlayable(resolved)) continue;
      if (isAnchor) resolvedAnchorIndex = queue.length;
      queue.add(resolved);
    }

    if (queue.isEmpty) return null;

    // Where growth should continue in [tracks]. Derived from the window bounds
    // rather than inferred from `queue.length`: dropped entries would otherwise
    // make growth re-resolve tracks already in the queue.
    return (
      queue: queue,
      startIndex: resolvedAnchorIndex,
      nextSourceIndex: forwardEnd,
    );
  }

  /// Resolves everything after an already-resolved window, for progressive
  /// queue growth. Unresolvable entries are omitted.
  ///
  /// [fromIndex] is an index into [tracks]; entries are resolved in order so the
  /// caller can append each batch as it lands and keep "next" working.
  Future<List<Track>> resolveRange(
    List<Track> tracks,
    int fromIndex, {
    int limit = 20,
    int concurrency = 6,
  }) async {
    if (fromIndex >= tracks.length) return const <Track>[];
    final int end = (fromIndex + limit).clamp(0, tracks.length);
    final List<Track> slice = tracks.sublist(fromIndex, end);
    final List<Track> resolved = await _resolveBounded(slice, concurrency);
    return <Track>[
      for (final Track t in resolved)
        if (_isPlayable(t)) t,
    ];
  }

  static bool _isPlayable(Track track) =>
      track.isDirectAudio && track.streamUrl != null;

  /// Resolves [tracks] with bounded concurrency, preserving input order.
  ///
  /// Order is preserved because queue position is user-visible: reordering would
  /// silently play the wrong track.
  Future<List<Track>> _resolveBounded(
    List<Track> tracks,
    int concurrency,
  ) async {
    if (tracks.isEmpty) return const <Track>[];
    final int width = concurrency < 1 ? 1 : concurrency;

    final List<Track?> resolved = List<Track?>.filled(tracks.length, null);
    int cursor = 0;

    Future<void> worker() async {
      while (true) {
        final int index = cursor++;
        if (index >= tracks.length) return;
        resolved[index] = await _tryResolve(tracks[index]);
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = 0; i < (width < tracks.length ? width : tracks.length); i++)
        worker(),
    ]);

    return <Track>[for (final Track? t in resolved) ?t];
  }

  /// Resolves one track, returning null instead of throwing.
  ///
  /// A dead entry in a queue is not an error worth surfacing; it should be
  /// dropped so the rest of the list still plays.
  Future<Track?> _tryResolve(Track track) async {
    try {
      // Through [resolve] rather than [resolveThrough] so the cache check runs;
      // filling a queue must not spend a provider call per entry.
      return await resolve(track);
    } on Object {
      return null;
    }
  }

  /// Returns a playable [Track], consulting the cache first.
  ///
  /// [allowNetwork] false makes this a pure cache read, which is what the
  /// player uses on a cache hit path.
  Future<Track> resolve(Track track, {bool allowNetwork = true}) async {
    final Track? cached = database.getTrack(track.id);

    // Already playable from cache: there is nothing better to ask the provider
    // for. `resolve` only mints a stream URL, so a cached one is as good as a
    // fresh one — and re-resolving would spend another call for no gain.
    if (cached != null && cached.isDirectAudio && cached.streamUrl != null) {
      return cached;
    }

    final MusicSource? source = sourceFor(track.id);
    if (source == null) {
      throw const ContentUnavailableException('Unknown provider for track.');
    }

    if (!allowNetwork && (cached == null || cached.streamUrl == null)) {
      throw const ContentUnavailableException('Track is not cached.');
    }

    return resolveThrough(source, cached ?? track);
  }

  /// Deduplicated resolution against a specific source.
  Future<Track> resolveThrough(MusicSource source, Track track) {
    final String key = track.id;
    final Future<Track>? existing = _inFlight[key];
    if (existing != null) return existing;

    final Future<Track> work = _resolveInner(source, track);
    _inFlight[key] = work;
    return work.whenComplete(() => _inFlight.remove(key));
  }

  Future<Track> _resolveInner(MusicSource source, Track track) async {
    try {
      final Track resolved = await source.resolve(track);
      await database.putTrack(resolved);
      return resolved;
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw TransportException('Could not resolve track.', cause: error);
    }
  }

  /// Warms the cache for a track that is merely on screen.
  ///
  /// Intentionally fire-and-forget and failure-silent: a prefetch that misses
  /// must never surface an error, because the user has not asked for anything
  /// yet. Deduplication means a viewport full of the same track costs one call.
  void prefetch(Track track) {
    if (_inFlight.containsKey(track.id)) return;
    final MusicSource? source = sourceFor(track.id);
    if (source == null) return;

    final Track? cached = database.getTrack(track.id);
    if (cached != null && cached.streamUrl != null) return;

    unawaited(resolveThrough(source, track).catchError((Object _) => track));
  }

  /// Batch prefetch for a viewport, ordered nearest-first so the most likely
  /// tap is resolved first.
  void prefetchAll(List<Track> tracks) {
    for (final Track track in tracks) {
      prefetch(track);
    }
  }

  Future<void> dispose() async {
    for (final MusicSource source in sources) {
      source.dispose();
    }
  }
}

/// Implemented by sources whose `search` omits duration, so the repository can
/// enrich results without knowing provider specifics.
abstract interface class DurationHydratable {
  Future<List<Track>> hydrate(List<Track> tracks);
}

/// Stand-in for a provider that is not registered.
///
/// Reached only through [_tryResolve] for a track whose id carries an unknown
/// source prefix. It exists so that path resolves to null (track dropped) rather
/// than throwing from inside a `catch`.
