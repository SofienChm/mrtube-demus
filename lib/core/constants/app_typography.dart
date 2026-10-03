import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type ramp. Tuned for dense music metadata: tight line heights, heavy display
/// weights for the player, generous letter-spacing on small caps labels.
abstract final class AppTypography {
  static const String _family = '.SF Pro Text';

  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: _family,
      fontSize: 34,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: AppColors.primaryText,
    ),
    headlineMedium: TextStyle(
      fontFamily: _family,
      fontSize: 26,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: AppColors.primaryText,
    ),
    titleLarge: TextStyle(
      fontFamily: _family,
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: AppColors.primaryText,
    ),
    titleMedium: TextStyle(
      fontFamily: _family,
      fontSize: 16,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryText,
    ),
    bodyLarge: TextStyle(
      fontFamily: _family,
      fontSize: 16,
      height: 1.4,
      color: AppColors.primaryText,
    ),
    bodyMedium: TextStyle(
      fontFamily: _family,
      fontSize: 14,
      height: 1.35,
      color: AppColors.secondaryText,
    ),
    bodySmall: TextStyle(
      fontFamily: _family,
      fontSize: 12,
      height: 1.3,
      color: AppColors.tertiaryText,
    ),
    labelSmall: TextStyle(
      fontFamily: _family,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.tertiaryText,
    ),
  );
}
