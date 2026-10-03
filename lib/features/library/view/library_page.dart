import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/models/playlist.dart';
import '../../../core/models/track.dart';
import '../../../core/services/database_service.dart';
import '../../player/bloc/player_bloc.dart';
import '../bloc/library_bloc.dart';

/// Favorites, playlists, and listening history, all local-first.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<LibraryBloc, LibraryState>(
          builder: (BuildContext context, LibraryState state) {
            final List<Track> recent = state.historyTracks(
              context.read<DatabaseService>(),
            );

            return DefaultTabController(
              length: 3,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'Your library',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'New playlist',
                          onPressed: () => _createPlaylist(context),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    indicatorColor: AppColors.accent,
                    labelColor: AppColors.accent,
                    unselectedLabelColor: AppColors.tertiaryText,
                    tabs: <Widget>[
                      Tab(text: 'Playlists'),
                      Tab(text: 'Favorites'),
                      Tab(text: 'History'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        _PlaylistsTab(playlists: state.playlists),
                        _FavoritesTab(tracks: state.favoriteTracks),
                        _HistoryTab(tracks: recent),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Future<void> _createPlaylist(BuildContext context) async {
    final TextEditingController nameController = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New playlist'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    nameController.dispose();

    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    context.read<LibraryBloc>().add(LibraryPlaylistCreated(name));
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return const _TabPlaceholder(
        icon: Icons.queue_music,
        title: 'No playlists yet',
        message: 'Tap the plus button to make one.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: playlists.length,
      itemBuilder: (BuildContext context, int index) {
        final Playlist playlist = playlists[index];
        return ListTile(
          leading: const Icon(
            Icons.queue_music,
            color: AppColors.secondaryText,
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${playlist.trackIds.length} '
            'track${playlist.trackIds.length == 1 ? '' : 's'}',
          ),
          trailing: IconButton(
            tooltip: 'Delete playlist',
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.tertiaryText,
            onPressed: () => _confirmDelete(context, playlist),
          ),
          onTap: () {},
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Playlist playlist) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete "${playlist.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    context.read<LibraryBloc>().add(LibraryPlaylistDeleted(playlist.id));
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _TabPlaceholder(
        icon: Icons.favorite_border,
        title: 'No favorites',
        message: 'Tap the heart on any track to save it here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: tracks.length,
      itemBuilder: (BuildContext context, int index) {
        final Track track = tracks[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          leading: CircleAvatar(
            backgroundColor: AppColors.surfaceHigh,
            backgroundImage: track.thumbnailUrl == null
                ? null
                : NetworkImage(track.thumbnailUrl!),
            child: track.thumbnailUrl == null
                ? const Icon(Icons.music_note, size: 18)
                : null,
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.play_arrow),
            color: AppColors.primaryText,
            onPressed: () => context.read<PlayerBloc>().add(
              PlayerTrackRequested(tracks: tracks, startIndex: index),
            ),
          ),
          onTap: () => context.read<PlayerBloc>().add(
            PlayerTrackRequested(tracks: tracks, startIndex: index),
          ),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _TabPlaceholder(
        icon: Icons.history,
        title: 'No history',
        message: 'Tracks you play will be listed here.',
      );
    }

    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () =>
                context.read<LibraryBloc>().add(const LibraryHistoryCleared()),
            child: const Text('Clear'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: tracks.length,
            itemBuilder: (BuildContext context, int index) {
              final Track track = tracks[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                leading: CircleAvatar(
                  backgroundColor: AppColors.surfaceHigh,
                  backgroundImage: track.thumbnailUrl == null
                      ? null
                      : NetworkImage(track.thumbnailUrl!),
                  child: track.thumbnailUrl == null
                      ? const Icon(Icons.music_note, size: 18)
                      : null,
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => context.read<PlayerBloc>().add(
                  PlayerTrackRequested(tracks: tracks, startIndex: index),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 44, color: AppColors.tertiaryText),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
