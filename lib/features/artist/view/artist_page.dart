import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/models/artist_summary.dart';
import '../../../core/models/track.dart';
import '../../../core/services/track_repository.dart';
import '../../../core/utils/formatters.dart';
import '../../player/bloc/player_bloc.dart';
import '../../search/widgets/track_tile.dart';
import '../bloc/artist_bloc.dart';

/// One artist's channel: identity, then everything they have published.
///
/// Reached by tapping the channel row at the top of search results, which is the
/// "see all" affordance track search itself cannot provide.
class ArtistPage extends StatelessWidget {
  const ArtistPage({required this.artist, super.key});

  final ArtistSummary artist;

  static Route<void> route(ArtistSummary artist) {
    return MaterialPageRoute<void>(builder: (_) => ArtistPage(artist: artist));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ArtistBloc>(
      create: (BuildContext context) => ArtistBloc(
        repository: context.read<TrackRepository>(),
        artist: artist,
      )..add(const ArtistLoadRequested()),
      child: Scaffold(
        backgroundColor: AppColors.obsidian,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _Header(artist: artist),
              Expanded(
                child: BlocBuilder<ArtistBloc, ArtistState>(
                  builder: (BuildContext context, ArtistState state) {
                    return switch (state.status) {
                      ArtistInitial() || ArtistLoading() => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      ArtistFailure(:final failure) => _ErrorBody(
                        message: failure.message,
                        onRetry: () => context.read<ArtistBloc>().add(
                          const ArtistLoadRequested(),
                        ),
                      ),
                      ArtistEmpty() => _EmptyBody(artist: artist),
                      ArtistSuccess() ||
                      ArtistLoadingMore() => _TrackList(state: state),
                    };
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> facts = <String>[
      if (artist.followerCount > 0)
        '${Formatters.count(artist.followerCount)} followers',
      '${artist.trackCount} ${artist.trackCount == 1 ? 'track' : 'tracks'}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            color: AppColors.primaryText,
            tooltip: 'Back',
          ),
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: artist.avatarUrl == null
                  ? Container(
                      color: AppColors.surface,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.person,
                        color: AppColors.secondaryText,
                      ),
                    )
                  : Image.network(
                      artist.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surface,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.person,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge,
                ),
                if (artist.handleLabel.isNotEmpty)
                  Text(
                    artist.handleLabel,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  facts.join(' · '),
                  style: text.bodySmall?.copyWith(
                    color: AppColors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The artist's tracks, with play-all and paging.
///
/// The queue passed to the player is the accumulated list, so tapping any track
/// also gives access to everything above and below it, including across page
/// boundaries.
class _TrackList extends StatefulWidget {
  const _TrackList({required this.state});

  final ArtistState state;

  @override
  State<_TrackList> createState() => _TrackListState();
}

class _TrackListState extends State<_TrackList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    // Prefetch before the user hits the bottom, so the next page is usually
    // already there by the time they get to it.
    if (remaining < 600 && widget.state.hasMore) {
      context.read<ArtistBloc>().add(const ArtistNextPageRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ArtistState state = widget.state;
    final List<Track> tracks = state.tracks;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _play(context, tracks, 0),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Play all (${Formatters.count(tracks.length)})'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            itemCount: tracks.length + (state.hasMore ? 1 : 0),
            itemBuilder: (BuildContext context, int index) {
              if (index >= tracks.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final Track track = tracks[index];
              return TrackTile(
                track: track,
                onTap: () => _play(context, tracks, index),
              );
            },
          ),
        ),
      ],
    );
  }

  void _play(BuildContext context, List<Track> tracks, int index) {
    context.read<PlayerBloc>().add(
      PlayerTrackRequested(tracks: tracks, startIndex: index),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.music_off,
              size: 48,
              color: AppColors.tertiaryText,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing playable from ${artist.name} yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
