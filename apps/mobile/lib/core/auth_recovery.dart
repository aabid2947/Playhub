import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Set to true when the user landed on the app via either a password-reset
/// link OR an invite acceptance link. The router redirects to
/// /reset-password whenever this flag is true so the user can set a
/// password before being dropped into their role shell.
final recoveryActiveProvider = StateProvider<bool>((_) => false);

/// Subscribes to Supabase auth state and flips [recoveryActiveProvider]
/// on password-recovery OR invite-acceptance events. Started once at boot.
final authRecoveryListenerProvider = Provider<StreamSubscription<AuthState>>(
  (ref) {
    final sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // Fresh invite signs the user in but they have no password yet.
      // Detect via lastSignInAt being null on first sign-in event.
      final user = data.session?.user;
      final isFreshInvite = data.event == AuthChangeEvent.signedIn
          && user != null
          && user.lastSignInAt == null
          && user.userMetadata?['role'] != null;
      if (data.event == AuthChangeEvent.passwordRecovery || isFreshInvite) {
        ref.read(recoveryActiveProvider.notifier).state = true;
      }
    });
    ref.onDispose(sub.cancel);
    return sub;
  },
);
