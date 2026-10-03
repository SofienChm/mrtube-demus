import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Artwork with a shimmering placeholder and a graceful failure state.
///
/// Rebuilt far more often than a plain `Image` would be (it sits in every list
/// row), so the placeholder is a cheap solid fill rather than anything that
/// repaints during the fade.
class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.url,
    this.size = 48,
    this.borderRadius,
    super.key,
  });

  final String? url;
  final double size;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(AppSpacing.radiusSm);

    final Widget placeholder = _ShimmerBox(size: size, radius: radius);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? _FallbackArtwork(size: size)
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) =>
                    _FallbackArtwork(size: size, isError: true),
              ),
      ),
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork({required this.size, this.isError = false});

  final double size;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: Icon(
        isError ? Icons.broken_image_outlined : Icons.music_note,
        size: size * 0.4,
        color: AppColors.tertiaryText,
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({required this.size, required this.radius});

  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceHigh,
      highlightColor: AppColors.surfaceHighest,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: radius,
        ),
      ),
    );
  }
}

/// Shimmering skeleton row used while the first page of a list is loading.
class TrackTileSkeleton extends StatelessWidget {
  const TrackTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceHigh,
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            _SkeletonBlock(width: 48, height: 48, radius: 6),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SkeletonBlock(width: 160, height: 12, radius: 4),
                  SizedBox(height: AppSpacing.sm),
                  _SkeletonBlock(width: 100, height: 10, radius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(radius.toDouble()),
      ),
    );
  }
}
