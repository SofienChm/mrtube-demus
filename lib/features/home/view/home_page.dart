import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/track.dart';
import '../../../core/services/database_service.dart';
import '../../library/bloc/library_bloc.dart';
import '../../player/bloc/player_bloc.dart';
import '../../player/view/player_page.dart';
import '../../search/widgets/track_tile.dart';

/// Landing tab: recently played and favorites, both served from local storage.
///
/// Nothing on this tab hits the network. It is the one surface guaranteed to
/// render on a cold start with no connectivity and no API key configured, which
/// is also what makes it a usable fallback when search is unavailable.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<LibraryBloc, LibraryState>(
          builder: (BuildContext context, LibraryState state) {
            final DatabaseService database = context.read<DatabaseService>();
            final List<Track> recent = state.historyTracks(database);

            return CustomScrollView(
              slivers: <Widget>[
                const SliverToBoxAdapter(child: _Greeting()),
                if (recent.isNotEmpty) ...<Widget>[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: 'Recently played'),
                  ),
                  SliverToBoxAdapter(
                    child: TrackCarousel(
                      tracks: recent,
                      onSelect: (_) => _openPlayer(context),
                    ),
                  ),
                ],
                if (state.favoriteTracks.isNotEmpty) ...<Widget>[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: 'Favorites'),
                  ),
                  SliverList.builder(
                    itemCount: state.favoriteTracks.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Track track = state.favoriteTracks[index];
                      return TrackTile(
                        track: track,
                        onTap: () => context.read<PlayerBloc>().add(
                          PlayerTrackRequested(
                            tracks: state.favoriteTracks,
                            startIndex: index,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (state.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            );
          },
        ),
      ),
    );
  }

  static void _openPlayer(BuildContext context) {
    Navigator.of(context).push(PlayerPage.route());
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final String hour = DateTime.now().hour.toString().padLeft(2, '0');
    final String greeting = switch (DateTime.now().hour) {
      < 12 => 'Good morning',
      < 18 => 'Good afternoon',
      _ => 'Good evening',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  greeting,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text('$hour:00', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceHigh,
            child: Icon(Icons.person, color: AppColors.secondaryText, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.graphic_eq, size: 48, color: AppColors.tertiaryText),
          const SizedBox(height: 12),
          Text(
            'Nothing here yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Search for something to play, and it will show up here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
