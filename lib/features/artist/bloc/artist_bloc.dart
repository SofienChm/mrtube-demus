import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';
import '../../../core/models/artist_summary.dart';
import '../../../core/models/track.dart';
import '../../../core/services/track_repository.dart';

part 'artist_event.dart';
part 'artist_state.dart';

/// Loads one artist's channel: their track list, paged, in provider order.
///
/// Deliberately does not reuse [SearchBloc]. An artist page has no query to
/// debounce, no cache-first path, and no cross-source reconciliation to do, so
/// sharing the search bloc's state machine would mean carrying a dozen
/// unrelated fields through every transition.
final class ArtistBloc extends Bloc<ArtistEvent, ArtistState> {
  ArtistBloc({required this.repository, required this.artist})
    : super(ArtistState(artist: artist)) {
    on<ArtistLoadRequested>(_onLoad, transformer: _droppable());
    on<ArtistNextPageRequested>(_onNextPage, transformer: _droppable());
  }

  /// Drops events that arrive while one is already being handled.
  ///
  /// A double-tap on "load more" must not fire two requests for the same
  /// cursor, and `ArtistBloc` is not restartable because a restarted load would
  /// discard tracks already on screen.
  static EventTransformer<E> _droppable<E>() =>
      (Stream<E> events, EventMapper<E> mapper) => events.asyncExpand(mapper);

  final TrackRepository repository;
  final ArtistSummary artist;

  Future<void> _onLoad(
    ArtistLoadRequested event,
    Emitter<ArtistState> emit,
  ) async {
    if (state.isBusy || state.tracks.isNotEmpty) return;
    emit(state.copyWith(status: const ArtistLoading(), clearError: true));

    try {
      final TrackPage page = await repository.artistTracks(artist);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: page.items.isEmpty
              ? const ArtistEmpty()
              : const ArtistSuccess(),
          tracks: page.items,
          nextPageToken: page.nextPageToken,
        ),
      );
    } on AppException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(status: ArtistFailure(toFailure(error))));
    }
  }

  Future<void> _onNextPage(
    ArtistNextPageRequested event,
    Emitter<ArtistState> emit,
  ) async {
    if (!state.hasMore || state.isBusy) return;

    emit(state.copyWith(status: const ArtistLoadingMore()));

    try {
      final TrackPage page = await repository.artistTracks(
        artist,
        pageToken: state.nextPageToken,
      );
      if (isClosed) return;

      // Offset paging means a provider can repeat or overlap a page. Deduping by
      // id keeps the list correct even if it does, instead of growing forever.
      final List<Track> merged = <Track>[...state.tracks];
      final Set<String> seen = <String>{for (final Track t in merged) t.id};
      for (final Track track in page.items) {
        if (seen.add(track.id)) merged.add(track);
      }

      emit(
        state.copyWith(
          status: const ArtistSuccess(),
          tracks: merged,
          nextPageToken: page.nextPageToken,
          // A null token means "no more pages". `copyWith` treats null as
          // "leave unchanged", so the cursor has to be cleared explicitly or
          // paging would never terminate.
          clearPageToken: page.nextPageToken == null,
        ),
      );
    } on AppException catch (error) {
      if (isClosed) return;
      final Failure failure = toFailure(error);

      // A failed page must not discard the pages already loaded; the user can
      // scroll to retry. Only a page that never loaded is a hard failure.
      emit(
        state.copyWith(
          status: state.tracks.isEmpty
              ? ArtistFailure(failure)
              : const ArtistSuccess(),
          error: failure,
        ),
      );
    }
  }
}
