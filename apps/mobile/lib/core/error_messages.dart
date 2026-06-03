import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps raw exceptions into short, user-facing strings.
///
/// Rule of thumb: never show Postgres error codes, stack traces, or raw
/// SDK messages to end users. Use this in `.when(error: ...)` blocks, in
/// snackbars after a try/catch, and wherever an error string would
/// otherwise hit the UI.
String friendlyError(Object error) {
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials') ||
        m.contains('invalid_grant')) {
      return 'Incorrect email or password.';
    }
    if (m.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (m.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (m.contains('user already registered')) {
      return 'An account with this email already exists.';
    }
    if (m.contains('password should be at least')) {
      return error.message;
    }
    return 'Sign-in failed. Please try again.';
  }

  if (error is PostgrestException) {
    final code = error.code ?? '';
    // 42501 = insufficient_privilege; PGRST301 = RLS violation in PostgREST.
    if (code == '42501' || code == 'PGRST301') {
      return "You don't have permission to do that.";
    }
    if (code.startsWith('23')) {
      // 23xxx = integrity constraint violations (unique, fk, not-null, check).
      if (code == '23505') return 'That record already exists.';
      if (code == '23503') return 'This is referenced by other records.';
      if (code == '23502') return 'A required field is missing.';
      if (code == '23514') return "That value isn't allowed.";
      return "That change isn't allowed.";
    }
    if (code == 'PGRST116') {
      return 'No matching record found.';
    }
    return 'Database error. Please try again.';
  }

  if (error is StorageException) {
    final m = error.message.toLowerCase();
    if (m.contains('payload too large') || m.contains('exceeded')) {
      return 'File is too large.';
    }
    if (m.contains('not found')) return 'File not found.';
    return 'Upload failed. Please try again.';
  }

  if (error is FunctionException) {
    final detail = error.details;
    if (detail is Map<String, dynamic>) {
      final err = detail['error']?.toString();
      if (err != null && err.isNotEmpty && err.length < 120) {
        return err;
      }
    }
    if (error.reasonPhrase?.isNotEmpty == true) {
      return 'Request failed: ${error.reasonPhrase}.';
    }
    return 'Request failed. Please try again.';
  }

  // Network failures bubble up as SocketException / TimeoutException.
  final s = error.toString().toLowerCase();
  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('connection closed') ||
      s.contains('network is unreachable')) {
    return 'Network error. Please check your connection.';
  }
  if (s.contains('timeoutexception') || s.contains('timed out')) {
    return 'The request timed out. Please try again.';
  }

  return 'Something went wrong. Please try again.';
}
