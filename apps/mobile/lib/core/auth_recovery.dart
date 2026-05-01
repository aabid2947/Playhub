import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Set to true when Supabase emits AuthChangeEvent.passwordRecovery —
/// the user landed on the app via a password-reset link. The router
/// redirects to /reset-password whenever this flag is true.
final recoveryActiveProvider = StateProvider<bool>((_) => false);

/// Subscribes to Supabase auth state and flips [recoveryActiveProvider]
/// on password-recovery events. Started once at app boot.
final authRecoveryListenerProvider = Provider<StreamSubscription<AuthState>>(
  (ref) {
    final sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(recoveryActiveProvider.notifier).state = true;
      }
    });
    ref.onDispose(sub.cancel);
    return sub;
  },
);
