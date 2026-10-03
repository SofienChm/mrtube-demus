import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_theme.dart';
import 'core/services/database_service.dart';
import 'core/services/track_repository.dart';
import 'features/library/bloc/library_bloc.dart';
import 'features/player/bloc/player_bloc.dart';
import 'features/player/data/youtube_embed_controller.dart';
import 'features/search/bloc/search_bloc.dart';
import 'features/shell/view/app_shell.dart';
import 'main.dart' show AppDependencies;

/// Root widget. Owns the bloc graph for the lifetime of the app.
///
/// Blocs are created once here rather than per-route because the player, the
/// mini-player, and the full-screen sheet must all observe the same playback
/// state; a route-scoped player bloc would desynchronise them.
class MrPlayApp extends StatelessWidget {
  const MrPlayApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        RepositoryProvider<DatabaseService>.value(value: dependencies.database),
        RepositoryProvider<TrackRepository>.value(
          value: dependencies.repository,
        ),
        // The player page mounts the webview surface, so it needs the same
        // controller instance the bloc drives.
        RepositoryProvider<YoutubeEmbedController>.value(
          value: dependencies.embedController,
        ),
      ],
      child: MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<PlayerBloc>(
            create: (_) => PlayerBloc(
              repository: dependencies.repository,
              audioHandler: dependencies.audioHandler,
              embedController: dependencies.embedController,
            ),
          ),
          BlocProvider<SearchBloc>(
            create: (_) => SearchBloc(repository: dependencies.repository),
          ),
          BlocProvider<LibraryBloc>(
            create: (_) => LibraryBloc(database: dependencies.database),
          ),
        ],
        child: MaterialApp(
          title: 'MrPlay',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
  }
}
