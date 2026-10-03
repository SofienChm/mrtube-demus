import 'package:flutter/material.dart';

/// Centralised palette. High-contrast dark, warm amber accent.
abstract final class AppColors {
  /// Base canvas. Near-black with a blue cast so the amber accent reads warm.
  static const Color obsidian = Color(0xFF121212);

  /// Slightly lifted surface for cards, mini-player, sheets.
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceHigh = Color(0xFF2C2C2E);
  static const Color surfaceHighest = Color(0xFF3A3A3C);

  static const Color accent = Color(0xFFFF9F0A);
  static const Color accentPressed = Color(0xFFE08C00);
  static const Color accentMuted = Color(0x33FF9F0A);

  static const Color primaryText = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFFB0B0B5);
  static const Color tertiaryText = Color(0xFF7C7C80);

  static const Color divider = Color(0xFF2E2E30);
  static const Color error = Color(0xFFFF453A);

  /// Scrim used behind the immersive full-screen player.
  static const Color scrim = Color(0xCC000000);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
