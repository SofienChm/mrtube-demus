import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the app's single dark theme.
///
/// High-contrast dark only by design: the spec calls for a strict matte-black
/// canvas with warm amber accents, so light mode is intentionally not offered
/// rather than being implemented half-heartedly.
abstract final class AppTheme {
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.obsidian,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData get dark {
    final ColorScheme scheme = const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.obsidian,
      secondary: AppColors.accent,
      onSecondary: AppColors.obsidian,
      surface: AppColors.obsidian,
      onSurface: AppColors.primaryText,
      error: AppColors.error,
      onError: AppColors.primaryText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.obsidian,
      canvasColor: AppColors.obsidian,
      textTheme: AppTypography.textTheme,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.obsidian,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: AppTypography.textTheme.titleLarge,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.obsidian,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentMuted,
        elevation: 0,
        height: AppSpacing.bottomNavHeight + AppSpacing.xl,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.tertiaryText,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppTypography.textTheme.labelSmall!.copyWith(
                  color: AppColors.accent,
                )
              : AppTypography.textTheme.labelSmall!,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 0.5,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceHigh,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accentMuted,
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.primaryText),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: AppColors.primaryText,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceHigh,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
