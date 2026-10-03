import '../models/track.dart';

/// The single seam between the app and whatever provides its audio.
///
/// Everything above this interface — BLoCs, caching, the audio pipeline, the
/// player UI — is provider-agnostic. Swapping or adding a provider is a single
/// new implementation plus a one-line change where sources are registered.
///
/// Implementations must be idempotent and safe to call concurrently: the
/// player calls [resolve] for prefetch while search is still paginating.
abstract interface class MusicSource {
  /// Stable identifier, e.g. `youtube`. Used as the prefix in [Track.id].
  String get id;

  /// Whether this provider can hand `just_audio` a direct URL, which is what
  /// background playback and lock-screen transport require.
  bool get supportsDirectAudio;

  /// Whether a search query costs quota on this provider. Providers with no
  /// quota (or no search at all) return false so the UI can skip caching
  /// pressure warnings.
  bool get searchIsQuotaBound;

  /// One page of results. [pageToken] null means "first page".
  Future<TrackPage> search(
    String query, {
    String? pageToken,
    int pageIndex = 0,
  });

  /// Enriches [track] with whatever is needed to play it.
  ///
  /// For [PlaybackCapability.directAudio] sources this must populate
  /// `streamUrl`. For [PlaybackCapability.embedOnly] sources it may be a no-op.
  /// Must never throw for an unplayable track; return the track unchanged and
  /// let the player surface the failure.
  Future<Track> resolve(Track track);

  /// Frees any long-lived resources (HTTP clients, isolates).
  void dispose();
}
