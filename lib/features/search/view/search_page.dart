import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/errors/failures.dart';
import '../../../core/models/artist_summary.dart';
import '../../../core/models/track.dart';
import '../../../core/search/search_sections.dart';
import '../../../core/widgets/artwork.dart';
import '../../artist/view/artist_page.dart';
import '../../artist/widgets/artist_channel_card.dart';
import '../../player/bloc/player_bloc.dart';
import '../bloc/search_bloc.dart';
import '../widgets/track_tile.dart';

/// Search tab.
///
/// The status hierarchy in [SearchStatus] is exhausted with a switch rather than
/// a chain of `if`s, so an empty result set and a failed request can never be
/// rendered with the same widget.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _SearchField(
                controller: _controller,
                onChanged: (String value) =>
                    context.read<SearchBloc>().add(SearchQueryChanged(value)),
                onSubmitted: (String value) =>
                    context.read<SearchBloc>().add(SearchQueryCommitted(value)),
                onCleared: () {
                  _controller.clear();
                  context.read<SearchBloc>().add(const SearchCleared());
                },
              ),
            ),
            Expanded(
              child: BlocBuilder<SearchBloc, SearchState>(
                builder: (BuildContext context, SearchState state) {
                  return Column(
                    children: <Widget>[
                      if (state.status is SearchRefreshing ||
                          state.status is SearchLoadingMore)
                        const LinearProgressIndicator(minHeight: 2),
                      Expanded(child: _buildBody(context, state)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SearchState state) {
    return switch (state.status) {
      SearchInitial() => const _IdleBody(),
      SearchLoading() => ListView.builder(
        itemCount: 8,
        itemBuilder: (_, _) => const TrackTileSkeleton(),
      ),
      SearchFailure(:final Failure failure) => _ErrorBody(
        failure: failure,
        onRetry: () => context.read<SearchBloc>().add(const SearchRetried()),
      ),
      SearchEmpty() => const _EmptyQueryBody(),
      SearchSuccess() ||
      SearchRefreshing() ||
      SearchLoadingMore() ||
      SearchCacheOnly() => _ResultsList(state: state),
    };
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCleared,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Songs, artists, anything',
        hintStyle: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppColors.tertiaryText),
        prefixIcon: const Icon(Icons.search, color: AppColors.tertiaryText),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (BuildContext context, TextEditingValue value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              onPressed: onCleared,
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.tertiaryText,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Paginated results, grouped the way a music app presents them.
///
/// [SearchSections] turns the ranked list into titled groups; this flattens them
/// into rows for a single lazily-built list. Every track row keeps its index in
/// the underlying ranked list, so tapping any row queues the results in the same
/// order they are displayed, including across section boundaries.
class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final List<Track> results = state.results;
    final bool showCacheNotice =
        state.usedCache && state.status is SearchCacheOnly;

    return Column(
      children: <Widget>[
        if (showCacheNotice) const _CacheNotice(),
        // The channel row sits above the tracks. When a query names an artist,
        // "who is this" is the prior question, and answering it first makes the
        // grouped tracks below legible as belonging to that channel.
        for (final ArtistSummary artist in state.artists)
          ArtistChannelCard(
            artist: artist,
            onTap: () => Navigator.of(context).push(ArtistPage.route(artist)),
          ),
        Expanded(
          child: Builder(
            builder: (BuildContext context) {
              final List<_Row> rows = _buildRows(state.query, results);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int index) {
                  final _Row row = rows[index];
                  return switch (row) {
                    _FooterRow() => _PaginationFooter(state: state),
                    _HeaderRow(:final String title) => _SectionTitle(
                      title: title,
                    ),
                    _TrackRow(:final Track track, :final int index) =>
                      _trackTile(context, track, results, index),
                    _TopResultRow(:final Track track, :final int index) =>
                      _TopResultCard(
                        track: track,
                        onTap: () => _play(context, results, index),
                      ),
                  };
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _trackTile(
    BuildContext context,
    Track track,
    List<Track> results,
    int index,
  ) {
    // Prefetch is driven by what is actually built, so a row that recycles
    // still warms the track it is about to show.
    context.read<SearchBloc>().add(SearchTrackVisible(results));

    return TrackTile(track: track, onTap: () => _play(context, results, index));
  }

  void _play(BuildContext context, List<Track> results, int index) {
    context.read<PlayerBloc>().add(
      PlayerTrackRequested(tracks: results, startIndex: index),
    );
  }

  static List<_Row> _buildRows(String query, List<Track> results) {
    if (results.isEmpty) return const <_Row>[];

    // Index of each track in the flat ranked list, so section rows can still
    // start playback at the right position.
    final Map<String, int> indexOf = <String, int>{
      for (int i = 0; i < results.length; i++) results[i].id: i,
    };

    final List<SearchSection> sections = SearchSections.build(query, results);
    final List<_Row> rows = <_Row>[];

    for (final SearchSection section in sections) {
      switch (section) {
        case TopResultSection(:final Track track, :final String? artist):
          rows.add(_TopResultRow(track: track, index: indexOf[track.id] ?? 0));
          if (artist != null) rows.add(_HeaderRow(title: 'Popular'));
        case TrackSection(:final String title, :final List<Track> tracks):
          // The header directly after a top result is emitted above, so skip a
          // duplicated "Popular" title here.
          final bool duplicateOfLast =
              title == 'Popular' &&
              rows.lastOrNull is _HeaderRow &&
              (rows.lastOrNull! as _HeaderRow).title == 'Popular';
          if (!duplicateOfLast) rows.add(_HeaderRow(title: title));
          for (final Track track in tracks) {
            rows.add(_TrackRow(track: track, index: indexOf[track.id] ?? 0));
          }
      }
    }

    rows.add(const _FooterRow());
    return rows;
  }
}

/// A rendered row. Rows carry the track's index in the flat result list so the
/// queue the player builds matches what the user sees.
sealed class _Row {
  const _Row();
}

final class _HeaderRow extends _Row {
  const _HeaderRow({required this.title});

  final String title;
}

final class _TrackRow extends _Row {
  const _TrackRow({required this.track, required this.index});

  final Track track;
  final int index;
}

final class _TopResultRow extends _Row {
  const _TopResultRow({required this.track, required this.index});

  final Track track;
  final int index;
}

final class _FooterRow extends _Row {
  const _FooterRow();
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// The single best match for the query, rendered large.
///
/// When a query names an artist this is that artist's newest release, which is
/// the thing a listener almost always meant to play first.
class _TopResultCard extends StatelessWidget {
  const _TopResultCard({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: Row(
          children: <Widget>[
            TrackArtwork(url: track.thumbnailUrl, size: 88),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(
            'End of results',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: TextButton.icon(
          onPressed: () =>
              context.read<SearchBloc>().add(const SearchNextPageRequested()),
          icon: const Icon(Icons.expand_more),
          label: const Text('Load more'),
        ),
      ),
    );
  }
}

class _CacheNotice extends StatelessWidget {
  const _CacheNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.accentMuted,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.offline_bolt, size: 14, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing saved results. Search quota for today is used up.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleBody extends StatelessWidget {
  const _IdleBody();

  @override
  Widget build(BuildContext context) {
    return const _MessageBody(
      icon: Icons.search,
      title: 'Find something to play',
      message:
          'Search results are cached on this device, so repeat '
          'lookups are instant and work offline.',
    );
  }
}

class _EmptyQueryBody extends StatelessWidget {
  const _EmptyQueryBody();

  @override
  Widget build(BuildContext context) {
    return const _MessageBody(
      icon: Icons.search_off,
      title: 'No matches',
      message: 'Try a different spelling, or search for the artist name.',
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: AppColors.tertiaryText),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.failure, required this.onRetry});

  final Failure failure;
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
              failure.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
