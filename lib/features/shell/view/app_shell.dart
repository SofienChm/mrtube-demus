import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../home/view/home_page.dart';
import '../../library/view/library_page.dart';
import '../../player/bloc/player_bloc.dart';
import '../../player/view/mini_player.dart';
import '../../search/view/search_page.dart';
import '../../settings/view/settings_page.dart';

/// Root navigation surface.
///
/// Uses an [IndexedStack] rather than rebuilding routes on tab switches: the
/// search field's cursor, scroll offsets, and the player bloc's queue all need
/// to survive a tab round-trip, and rebuilding them on every switch is the most
/// common source of "my search box cleared itself" bugs.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    SearchPage(),
    LibraryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final bool hasTrack = context.select<PlayerBloc, bool>(
      (PlayerBloc bloc) => bloc.state.hasTrack,
    );

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Sits above the nav bar so the transport is reachable from every
          // tab without a dedicated route.
          if (hasTrack) const MiniPlayer(),
          NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.accentMuted,
              labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
                (Set<WidgetState> states) =>
                    Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: states.contains(WidgetState.selected)
                          ? AppColors.accent
                          : AppColors.tertiaryText,
                    ),
              ),
            ),
            child: NavigationBar(
              height: AppSpacing.bottomNavHeight,
              selectedIndex: _index,
              onDestinationSelected: (int value) =>
                  setState(() => _index = value),
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
