import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/formatters.dart';

/// Diagnostics and local storage controls.
///
/// Also the place where the app is honest about its constraints: a user with no
/// `YOUTUBE_API_KEY` sees exactly why search returns nothing, rather than an
/// unexplained empty state.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _cacheSizeBytes;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final int bytes = await context.read<DatabaseService>().cacheSizeBytes();
    if (!mounted) return;
    setState(() => _cacheSizeBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    const String apiKey = String.fromEnvironment('YOUTUBE_API_KEY');
    final bool hasApiKey = apiKey.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (!hasApiKey)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: _WarningBanner(
                  message:
                      'No YouTube API key is configured, so search is '
                      'disabled. Cached results still work. Rebuild with '
                      '--dart-define=YOUTUBE_API_KEY=... to enable it.',
                ),
              ),
            _Section(
              title: 'Playback',
              children: const <Widget>[
                _InfoTile(
                  icon: Icons.headphones,
                  label: 'Direct audio',
                  detail: 'Plays in the background with lock-screen controls.',
                ),
                _InfoTile(
                  icon: Icons.open_in_browser,
                  label: 'Embedded playback',
                  detail:
                      'Plays inside the app only. Stops when you leave the '
                      'app, because the official web player is suspended.',
                ),
              ],
            ),
            _Section(
              title: 'Storage',
              children: <Widget>[
                _InfoTile(
                  icon: Icons.sd_storage,
                  label: 'Cached data',
                  detail: _cacheSizeBytes == null
                      ? 'Measuring...'
                      : Formatters.bytes(_cacheSizeBytes!),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.cleaning_services_outlined,
                    color: AppColors.secondaryText,
                  ),
                  title: const Text('Clear search cache'),
                  subtitle: const Text(
                    'Frees space. Favorites and playlists are kept.',
                  ),
                  onTap: () => _clearCache(context),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.history_toggle_off,
                    color: AppColors.secondaryText,
                  ),
                  title: const Text('Clear listening history'),
                  onTap: () => context.read<DatabaseService>().clearHistory(),
                ),
              ],
            ),
            _Section(
              title: 'About',
              children: const <Widget>[
                _InfoTile(
                  icon: Icons.info_outline,
                  label: 'MrPlay',
                  detail: 'Version 0.1.0',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    await context.read<DatabaseService>().clearMetadataCache();
    if (!context.mounted) return;
    await _loadCacheSize();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Search cache cleared')));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppColors.tertiaryText,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.secondaryText),
      title: Text(label),
      subtitle: Text(detail),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber, size: 18, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}
