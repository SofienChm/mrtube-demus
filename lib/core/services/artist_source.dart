import '../models/artist_summary.dart';
import '../models/track.dart';

/// A provider that has real artist/channel accounts.
///
/// Deliberately separate from [MusicSource]: track search answers "which song
/// matches these words", while this answers "who is this person". Only some
/// providers model uploaders as addressable channels at all, and a provider
/// without them should not be forced to return empty stubs — callers feature-detect
/// with `is` instead.
abstract interface class ArtistSource {
  /// Searches artist accounts by name or handle.
  ///
  /// Implementations should return raw provider order. Relevance is decided by
  /// `ArtistUserRanker`, because provider user-search ordering is unreliable
  /// enough to rank an unrelated account first.
  Future<List<ArtistSummary>> searchUsers(String query);

  /// One page of an artist's own tracks, in the provider's own order (typically
  /// newest first). [artistId] is [ArtistSummary.sourceId].
  Future<TrackPage> fetchArtistTracks(String artistId, {String? pageToken});
}
