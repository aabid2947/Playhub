import 'package:flutter_test/flutter_test.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('friendlyError', () {
    test('AuthException — invalid login credentials', () {
      final m = friendlyError(
        const AuthException('Invalid login credentials'),
      );
      expect(m, 'Incorrect email or password.');
    });

    test('AuthException — email not confirmed', () {
      final m = friendlyError(
        const AuthException('Email not confirmed'),
      );
      expect(m, contains('confirm your email'));
    });

    test('AuthException — already registered', () {
      final m = friendlyError(
        const AuthException('User already registered'),
      );
      expect(m, contains('already exists'));
    });

    test('PostgrestException — RLS deny (42501)', () {
      final m = friendlyError(
        const PostgrestException(
          message: 'permission denied for table foo',
          code: '42501',
        ),
      );
      expect(m, contains("don't have permission"));
    });

    test('PostgrestException — unique violation (23505)', () {
      final m = friendlyError(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        ),
      );
      expect(m, contains('already exists'));
    });

    test('PostgrestException — fk violation (23503)', () {
      final m = friendlyError(
        const PostgrestException(
          message: 'foreign key violation',
          code: '23503',
        ),
      );
      expect(m, contains('referenced'));
    });

    test('PostgrestException — not null (23502)', () {
      final m = friendlyError(
        const PostgrestException(
          message: 'null value violates not-null',
          code: '23502',
        ),
      );
      expect(m, contains('required field'));
    });

    test('PostgrestException — PGRST116 not-found', () {
      final m = friendlyError(
        const PostgrestException(
          message: 'No rows',
          code: 'PGRST116',
        ),
      );
      expect(m, contains('No matching record'));
    });

    test('Generic Exception — fallback message', () {
      final m = friendlyError(Exception('mystery'));
      expect(m, 'Something went wrong. Please try again.');
    });

    test('SocketException-like string', () {
      final m = friendlyError(Exception('SocketException: Failed host lookup'));
      expect(m, contains('Network error'));
    });

    test('TimeoutException-like string', () {
      final m = friendlyError(Exception('TimeoutException: timed out'));
      expect(m, contains('timed out'));
    });
  });
}
