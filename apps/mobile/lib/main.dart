import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/auth_recovery.dart';
import 'package:playhub/core/env.dart';
import 'package:playhub/core/error_handler.dart';
import 'package:playhub/core/router.dart';
import 'package:playhub/core/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // runZonedGuarded catches any async error that escapes our other hooks
  // (e.g. unawaited Futures inside third-party packages).
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Install global error hooks after binding init so we can detect
    // whether we're running under a test binding (which forbids
    // ErrorWidget.builder / FlutterError.onError overrides).
    AppErrorHandler.install();

    if (!Env.isConfigured) {
      runApp(const _ConfigErrorApp());
      return;
    }

    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
    } on Object catch (e, st) {
      debugPrint('Supabase init failed: $e\n$st');
      AppErrorHandler.showError(
        "Couldn't connect to the server. Please check your connection.",
      );
    }

    runApp(const ProviderScope(child: PlayHubApp()));
  }, (error, stack) {
    debugPrint('Uncaught zoned error: $error\n$stack');
    AppErrorHandler.showError('Something went wrong.');
  });
}

class PlayHubApp extends ConsumerWidget {
  const PlayHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Boot the auth-state listener (its provider has side effects).
    ref.watch(authRecoveryListenerProvider);

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'PlayHub',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // themeMode defaults to ThemeMode.system — follows the device's
      // light/dark setting; both are themed vivid violet.
      routerConfig: router,
      scaffoldMessengerKey: AppErrorHandler.rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Missing Supabase configuration',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Run with --dart-define=SUPABASE_URL=... '
                  '--dart-define=SUPABASE_ANON_KEY=...',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
