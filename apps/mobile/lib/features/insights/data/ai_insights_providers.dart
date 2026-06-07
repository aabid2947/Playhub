import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/insights/data/ai_insights.dart';

/// AI insight for one student, via the `ai-insights` edge function.
///
/// The Gemini key + the model call live entirely in that function — the app
/// only sends a `student_id` (the function gathers metrics under the caller's
/// RLS and returns a de-identified summary). `.family` keyed by student id so
/// each student's insight caches independently; `ref.invalidate(...)` to
/// regenerate.
final studentInsightProvider =
    FutureProvider.family<StudentInsight, String>((ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  // Non-2xx responses throw FunctionException (carrying our {error} body),
  // which `friendlyError` unwraps for the UI — so we only handle success here.
  final res = await client.functions.invoke(
    'ai-insights',
    body: {'student_id': studentId},
  );
  final data = res.data;
  if (data is Map && data['insight'] is Map) {
    return StudentInsight.fromMap(
      Map<String, dynamic>.from(data['insight'] as Map),
    );
  }
  throw Exception('Could not generate insights.');
});
