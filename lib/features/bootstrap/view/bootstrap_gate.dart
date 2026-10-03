import 'package:flutter/material.dart';

import '../../../app.dart' show MrPlayApp;
import '../../../core/constants/app_theme.dart';
import '../../../main.dart' show AppDependencies;

/// Runs [AppDependencies.bootstrap] behind a visible gate.
///
/// Bootstrap is async and touches platform channels (Hive, `audio_service`), so
/// it can fail or stall. Awaiting it before [runApp] means any such failure
/// presents as a black screen with nothing on screen and no clue why — the worst
/// possible failure mode. This renders immediately, reports which stage is
/// running, and shows the actual error if one occurs.
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key});

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  AppDependencies? _dependencies;
  String _stage = 'starting';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _stage = 'starting';
    });

    try {
      final AppDependencies dependencies = await AppDependencies.bootstrap(
        onStage: (String stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (mounted) setState(() => _dependencies = dependencies);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppDependencies? dependencies = _dependencies;
    if (dependencies != null) return MrPlayApp(dependencies: dependencies);

    return MaterialApp(
      title: 'MrPlay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: _scaffold(),
    );
  }

  Widget _scaffold() {
    final Object? error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: error == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        _stage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.error_outline,
                        size: 40,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'MrPlay could not start',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        // Surfaced verbatim: this is the only diagnostic
                        // available without a debugger attached.
                        '$error',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'stage: $_stage',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
