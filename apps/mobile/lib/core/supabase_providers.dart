import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(supabaseClientProvider));
});

/// Streams auth state changes; emits null when signed out.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// Current Supabase session, or null.
final sessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.maybeWhen(
    data: (state) => state?.session ?? Supabase.instance.client.auth.currentSession,
    orElse: () => Supabase.instance.client.auth.currentSession,
  );
});
