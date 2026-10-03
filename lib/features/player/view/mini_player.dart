import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/models/track.dart';
import '../../../core/widgets/artwork.dart';
import '../bloc/player_bloc.dart';
import 'player_page.dart';

/// Persistent transport bar shown above the bottom navigation.
///
/// Split into three narrowly-scoped subtrees. The position stream ticks several
/// times per second, so only [_MiniProgress] subscribes to it; the title,
/// artwork, and buttons are driven by `select` on fields that change far less
/// often. Rebuilding the whole bar on every tick would re-decode artwork and
/// churn the Hero at 10 Hz.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static String heroTagFor(String trackId) => 'player-artwork-$trackId';

  @override
  Widget build(BuildContext context) {
    final Track? track = context.select<PlayerBloc, Track?>(
      (PlayerBloc bloc) => bloc.state.current,
    );
    if (track == null) return const SizedBox.shrink();

    return Material(
      color: AppColors.surfaceHigh,
      child: InkWell(
        onTap: () => Navigator.of(context).push(PlayerPage.route()),
        child: SizedBox(
          height: AppSpacing.miniPlayerHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _MiniProgress(),
              Expanded(
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: AppSpacing.md),
                    Hero(
                      tag: heroTagFor(track.id),
                      child: TrackArtwork(
                        url: track.thumbnailUrl,
                        size: 40,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
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
                    const _MiniPlayPauseButton(),
                    _MiniActionButton(
                      icon: Icons.skip_next,
                      onPressed: () => context.read<PlayerBloc>().add(
                        const PlayerNextRequested(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayPauseButton extends StatelessWidget {
  const _MiniPlayPauseButton();

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = context.select<PlayerBloc, bool>(
      (PlayerBloc bloc) => bloc.state.isPlaying,
    );
    return _MiniActionButton(
      icon: isPlaying ? Icons.pause : Icons.play_arrow,
      onPressed: () =>
          context.read<PlayerBloc>().add(const PlayerTogglePlayPause()),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: AppColors.primaryText,
    );
  }
}

/// Hairline progress indicator fed by the position stream.
///
/// Deliberately not a [Slider]: the mini player is not a seek target, and a
/// slider would claim the drag gesture from the InkWell that opens the player.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context) {
    final double progress = context.select<PlayerBloc, double>(
      (PlayerBloc bloc) => bloc.state.progress,
    );

    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: AppColors.divider,
      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
    );
  }
}
