import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:playhub/main.dart' as app;

/// Integration-test harness + entrypoint smoke.
///
/// Runs headless under `flutter test integration_test/app_boot_test.dart`
/// (no emulator, no backend). It exercises the real `main()` entrypoint and
/// asserts the env-config guard path renders, proving the app boots and the
/// integration harness is wired.
///
/// Full per-journey UI E2E (login → role dashboards → CRUD) is a deliberate
/// follow-up: it needs a running device/emulator, the app built with
/// `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` pointed at
/// a seeded local Supabase, and is inherently slower/flakier than the
/// deterministic layers (RLS matrix, business flows, pgTAP, Deno, Flutter
/// unit). Add those journeys here against `app.main()` once a device target is
/// provisioned in CI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots; with no Supabase config it shows the config guard', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    // No --dart-define SUPABASE_URL/ANON_KEY in the test env → Env.isConfigured
    // is false, so main() renders the guard instead of initialising Supabase.
    expect(find.text('Missing Supabase configuration'), findsOneWidget);
  });
}
