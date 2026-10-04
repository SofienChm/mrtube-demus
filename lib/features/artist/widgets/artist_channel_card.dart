import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/models/artist_summary.dart';
import '../../../core/utils/formatters.dart';

/// The artist's channel, shown above the tracks a query matched.
///
/// This exists because track search cannot answer "who is this person". A
/// provider will return songs that merely mention the name, and the listener has
/// no way to tell those apart from the artist themself. One row carrying the
/// avatar, the handle, and the follower count answers it directly, and makes the
/// rest of the list legible as "more from this channel".
class ArtistChannelCard extends StatelessWidget {
  const ArtistChannelCard({
    required this.artist,
    required this.onTap,
    super.key,
  });

  final ArtistSummary artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                _Avatar(artist: artist),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              artist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                          ),
                          if (artist.isVerified) ...<Widget>[
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(
                              Icons.verified,
                              size: 14,
                              color: AppColors.accent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.secondaryText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Handle first, because it is what a listener would type to find this
  /// channel again. Follower count follows, since on this platform a large
  /// follower count is often the only signal that an identically named account
  /// is the notable one.
  String _subtitle() {
    final List<String> parts = <String>[];
    if (artist.handleLabel.isNotEmpty) parts.add(artist.handleLabel);
    if (artist.followerCount > 0) {
      parts.add('${Formatters.count(artist.followerCount)} followers');
    }
    if (parts.isEmpty) {
      parts.add(
        artist.trackCount == 1 ? '1 track' : '${artist.trackCount} tracks',
      );
    }
    return parts.join(' · ');
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context) {
    // Circular because Audius channels are people; the square artwork used
    // elsewhere would read as an album.
    return ClipOval(
      child: SizedBox(
        width: 52,
        height: 52,
        child: artist.avatarUrl == null
            ? const _AvatarFallback()
            : Image.network(
                artist.avatarUrl!,
                fit: BoxFit.cover,
                // A dead avatar URL must not leave a broken-image box where the
                // listener is trying to recognise the artist.
                errorBuilder: (_, _, _) => const _AvatarFallback(),
                loadingBuilder: (_, Widget child, _) => child,
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.obsidian,
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: AppColors.secondaryText, size: 26),
    );
  }
}
