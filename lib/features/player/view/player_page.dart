import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    hide PlayerState;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/errors/failures.dart';
import '../../../core/models/track.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/artwork.dart';
import '../../library/bloc/library_bloc.dart';
import '../bloc/player_bloc.dart';
import '../data/youtube_embed_controller.dart';
import 'mini_player.dart';

/// Full-screen now-playing surface, pushed over the shell.
///
/// The artwork shares a [Hero] tag with the mini player, so the transition is a
/// continuous expansion rather than a cross-fade between two unrelated cards.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const PlayerPage(),
      transitionsBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            return FadeTransition(opacity: animation, child: child);
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Track? track = context.select<PlayerBloc, Track?>(
      (PlayerBloc bloc) => bloc.state.current,
    );
    if (track == null) {
      return const Scaffold(
        backgroundColor: AppColors.obsidian,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const _PlayerHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    _PlayerArtwork(track: track),
                    const SizedBox(height: AppSpacing.xl),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: _TrackMeta(track: track),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _Scrubber(),
                    const SizedBox(height: AppSpacing.sm),
                    const _TransportControls(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 30),
            color: AppColors.primaryText,
          ),
          const Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: AppColors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          const _EmbedOnlyBadge(),
          const SizedBox(width: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// Warns that this source cannot play in the background.
///
/// Shown only for embed-only tracks, where sending the app to the background
/// genuinely stops the audio. Hiding it would look like a bug to the user.
class _EmbedOnlyBadge extends StatelessWidget {
  const _EmbedOnlyBadge();

  @override
  Widget build(BuildContext context) {
    final bool isEmbedOnly = context.select<PlayerBloc, bool>(
      (PlayerBloc bloc) => bloc.state.isEmbedOnly,
    );
    if (!isEmbedOnly) return const SizedBox(width: AppSpacing.lg);

    return Tooltip(
      message: 'Plays inside the app only. Background audio is unavailable.',
      child: const Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 14, color: AppColors.tertiaryText),
          SizedBox(width: AppSpacing.xs),
          Text('In-app only', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// Cover art, or the live embed surface for embed-only tracks.
class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final bool isEmbedOnly = context.select<PlayerBloc, bool>(
      (PlayerBloc bloc) => bloc.state.isEmbedOnly,
    );

    final Widget child = isEmbedOnly
        ? ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: YoutubePlayer(
                controller: context.read<YoutubeEmbedController>().controller,
              ),
            ),
          )
        : Hero(
            tag: MiniPlayer.heroTagFor(track.id),
            child: TrackArtwork(
              url: track.thumbnailUrl,
              size: 280,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: child,
    );
  }
}

class _TrackMeta extends StatelessWidget {
  const _TrackMeta({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final bool isFavorite = context.select<LibraryBloc, bool>(
      (LibraryBloc bloc) => bloc.state.isFavorite(track.id),
    );

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () =>
              context.read<LibraryBloc>().add(LibraryFavoriteToggled(track.id)),
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          color: isFavorite ? AppColors.accent : AppColors.secondaryText,
        ),
      ],
    );
  }
}

/// Seek bar with elapsed/total labels.
class _Scrubber extends StatelessWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerState>(
      // The scrubber is the one place a per-tick rebuild is required, so scope
      // it here rather than letting the whole page rebuild.
      buildWhen: (PlayerState previous, PlayerState current) =>
          previous.displayPosition != current.displayPosition ||
          previous.duration != current.duration ||
          previous.isEmbedOnly != current.isEmbedOnly,
      builder: (BuildContext context, PlayerState state) {
        final Duration total = state.duration ?? Duration.zero;
        final int totalMs = total.inMilliseconds;
        final int positionMs = state.displayPosition.inMilliseconds.clamp(
          0,
          totalMs,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: <Widget>[
              Slider(
                value: totalMs <= 0 ? 0 : positionMs.toDouble(),
                max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                onChanged: totalMs <= 0
                    ? null
                    : (double value) => context.read<PlayerBloc>().add(
                        PlayerPositionPreviewed(
                          Duration(milliseconds: value.round()),
                        ),
                      ),
                onChangeEnd: (double value) => context.read<PlayerBloc>().add(
                  PlayerSeekRequested(Duration(milliseconds: value.round())),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      Formatters.duration(state.displayPosition),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      totalMs <= 0 ? '--:--' : Formatters.duration(total),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context) {
    final PlayerState state = context.watch<PlayerBloc>().state;
    final PlayerBloc bloc = context.read<PlayerBloc>();

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              onPressed: () => bloc.add(const PlayerShuffleToggled()),
              icon: const Icon(Icons.shuffle),
              color: state.isShuffleOn
                  ? AppColors.accent
                  : AppColors.tertiaryText,
            ),
            IconButton(
              iconSize: 36,
              onPressed: () => bloc.add(const PlayerPreviousRequested()),
              icon: const Icon(Icons.skip_previous),
              color: AppColors.primaryText,
            ),
            _PlayPauseButton(state: state, onPressed: bloc),
            IconButton(
              iconSize: 36,
              onPressed: () => bloc.add(const PlayerNextRequested()),
              icon: const Icon(Icons.skip_next),
              color: AppColors.primaryText,
            ),
            IconButton(
              onPressed: () => bloc.add(const PlayerRepeatToggled()),
              icon: Icon(
                state.repeatMode == AudioServiceRepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
              ),
              color: state.repeatMode == AudioServiceRepeatMode.none
                  ? AppColors.tertiaryText
                  : AppColors.accent,
            ),
          ],
        ),
        if (state.status == PlayerStatus.error && state.failure != null) ...[
          const SizedBox(height: AppSpacing.md),
          _PlaybackError(failure: state.failure!),
        ],
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.state, required this.onPressed});

  final PlayerState state;
  final PlayerBloc onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isBusy =
        state.status == PlayerStatus.loading ||
        state.status == PlayerStatus.buffering;

    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: AppColors.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onPressed.add(const PlayerTogglePlayPause()),
          child: Center(
            child: isBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.obsidian,
                      ),
                    ),
                  )
                : Icon(
                    state.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 34,
                    color: AppColors.obsidian,
                  ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              failure.message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(
            onPressed: () =>
                context.read<PlayerBloc>().add(const PlayerFailureDismissed()),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
