import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/models/track.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/artwork.dart';
import '../../library/bloc/library_bloc.dart';
import '../../player/bloc/player_bloc.dart';

/// One row in a track list.
///
/// Stateless and cheap by construction: it reads only the booleans it needs from
/// surrounding blocs via `select`, so a favorite toggle on one row does not
/// rebuild its neighbours.
class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.track,
    required this.onTap,
    this.onMore,
    this.showArtwork = true,
    this.trailing,
    this.dense = false,
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  final bool showArtwork;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bool isFavorite = context.select<LibraryBloc, bool>(
      (LibraryBloc bloc) => bloc.state.isFavorite(track.id),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: dense ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              if (showArtwork) ...<Widget>[
                TrackArtwork(url: track.thumbnailUrl, size: dense ? 40 : 48),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.duration == null
                          ? track.artist
                          : '${track.artist}  ${Formatters.duration(track.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onMore != null)
                IconButton(
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz, size: 20),
                  color: AppColors.tertiaryText,
                  visualDensity: VisualDensity.compact,
                )
              else
                _FavoriteButton(trackId: track.id, isFavorite: isFavorite),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.trackId, required this.isFavorite});

  final String trackId;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () =>
          context.read<LibraryBloc>().add(LibraryFavoriteToggled(trackId)),
      icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, size: 20),
      color: isFavorite ? AppColors.accent : AppColors.tertiaryText,
      visualDensity: VisualDensity.compact,
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
    );
  }
}

/// Horizontally scrolling strip of square covers.
///
/// Kept as its own widget so the parent only rebuilds when the track list
/// identity changes, not on every playback tick.
class TrackCarousel extends StatelessWidget {
  const TrackCarousel({
    required this.tracks,
    required this.onSelect,
    this.height = 160,
    super.key,
  });

  final List<Track> tracks;
  final void Function(Track track) onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final Track track = tracks[index];
          return GestureDetector(
            onTap: () {
              final PlayerBloc player = context.read<PlayerBloc>();
              player.add(
                PlayerTrackRequested(tracks: tracks, startIndex: index),
              );
              onSelect(track);
            },
            child: SizedBox(
              width: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TrackArtwork(
                    url: track.thumbnailUrl,
                    size: height,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Section header with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
