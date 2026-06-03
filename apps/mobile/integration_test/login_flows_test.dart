import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:playhub/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

/// End-to-end login smoke tests against the live demo backend.
///
/// Run with:
///   flutter test integration_test/login_flows_test.dart \
///     -d <device> \
///     --dart-define=SUPABASE_URL=https://<...>.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=<anon> \
///     --dart-define=RAZORPAY_KEY_ID=rzp_test_<...>
///
/// Each test signs in as a demo account, asserts the dashboard for that
/// role renders, then signs out via the page object below. Demo creds
/// match the seeded data documented in /DEMO_CREDENTIALS.md.
const _demoPassword = 'Demo@1234';

const _demoAccounts = <_DemoAccount>[
  _DemoAccount(
    role: 'academy_owner',
    email: 'owner@playhubdemo.in',
    // Owner shell uses bottom-nav labels Home, Students, Coaches, Batches…
    expectAnyText: ['Home', 'Students', 'Batches'],
  ),
  _DemoAccount(
    role: 'academy_admin',
    email: 'admin@playhubdemo.in',
    expectAnyText: ['Home', 'Students', 'Batches'],
  ),
  _DemoAccount(
    role: 'center_admin',
    email: 'centeradmin@playhubdemo.in',
    expectAnyText: ['Home', 'Students', 'Batches'],
  ),
  _DemoAccount(
    role: 'head_coach',
    email: 'headcoach@playhubdemo.in',
    expectAnyText: ['Home', 'Batches', 'Students'],
  ),
  _DemoAccount(
    role: 'coach',
    email: 'coach@playhubdemo.in',
    expectAnyText: ['Home', 'Batches', 'Students'],
  ),
  _DemoAccount(
    role: 'trainer',
    email: 'trainer@playhubdemo.in',
    expectAnyText: ['Home', 'Batches', 'Students'],
  ),
  _DemoAccount(
    role: 'parent',
    email: 'parent@playhubdemo.in',
    expectAnyText: ['Home', 'Events', 'Outstanding dues'],
  ),
  _DemoAccount(
    role: 'student',
    email: 'student@playhubdemo.in',
    expectAnyText: ['Home', 'Upcoming sessions'],
  ),
  _DemoAccount(
    role: 'super_admin',
    email: 'superadmin@playhubdemo.in',
    expectAnyText: ['Academies', 'Health', 'Plans'],
  ),
];

class _DemoAccount {
  const _DemoAccount({
    required this.role,
    required this.email,
    required this.expectAnyText,
  });
  final String role;
  final String email;
  final List<String> expectAnyText;
}

Future<void> _bootApp(WidgetTester tester) async {
  await app.main();
  // Boot may take a moment to reach the splash → login redirect.
  await tester.pumpAndSettle(const Duration(seconds: 4));
}

/// Tests in the same binding share Supabase auth state. Sign out before
/// each test so we always start at the login page.
Future<void> _resetAuth(WidgetTester tester) async {
  try {
    await Supabase.instance.client.auth.signOut();
  } on Object {
    // First test: Supabase not yet initialized — that's fine.
  }
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> _signIn(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  // The login page has two TextFields (email, password).
  final emailField = find.byType(TextField).at(0);
  final passwordField = find.byType(TextField).at(1);
  expect(emailField, findsOneWidget);
  expect(passwordField, findsOneWidget);

  await tester.enterText(emailField, email);
  await tester.enterText(passwordField, password);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  final signInBtn = find.widgetWithText(FilledButton, 'Sign in');
  expect(signInBtn, findsOneWidget);
  await tester.tap(signInBtn);

  // Sign-in does a network round-trip + profile fetch + role routing.
  await tester.pumpAndSettle(const Duration(seconds: 8));
}

void _expectAnyText(List<String> any) {
  final found = any.any((t) => find.text(t).evaluate().isNotEmpty);
  expect(
    found,
    isTrue,
    reason:
        'Expected one of $any to appear on the post-login screen, found none.',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final account in _demoAccounts) {
    testWidgets('sign in as ${account.role}', (tester) async {
      await _bootApp(tester);
      await _resetAuth(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // We should land on the login page (no session yet).
      expect(find.text('Sign in'), findsWidgets);

      await _signIn(
        tester,
        email: account.email,
        password: _demoPassword,
      );

      // After sign-in we expect to be on the role's dashboard.
      _expectAnyText(account.expectAnyText);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  testWidgets('login with wrong password shows friendly error', (tester) async {
    await _bootApp(tester);
    await _resetAuth(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign in'), findsWidgets);

    await _signIn(
      tester,
      email: 'owner@playhubdemo.in',
      password: 'definitely-wrong',
    );
    // We should still be on the login screen and a friendly error string
    // should be visible. Specifically: "Incorrect email or password."
    // (mapped by friendlyError from AuthException).
    expect(
      find.textContaining('Incorrect email or password'),
      findsOneWidget,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
