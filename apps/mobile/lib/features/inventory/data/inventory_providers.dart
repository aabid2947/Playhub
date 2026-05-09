import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final inventoryItemsProvider =
    FutureProvider<List<InventoryItem>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('inventory_items')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('name');
  return (rows as List)
      .map((r) => InventoryItem.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final lowStockItemsProvider =
    Provider<List<InventoryItem>>((ref) {
  final all = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
  return all.where((i) => i.lowStock).toList(growable: false);
});

final inventoryCategoriesProvider =
    FutureProvider<List<InventoryCategory>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('inventory_categories')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('name');
  return (rows as List)
      .map((r) => InventoryCategory.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final vendorsProvider = FutureProvider<List<Vendor>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('vendors')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('name');
  return (rows as List)
      .map((r) => Vendor.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final itemMovementsProvider =
    FutureProvider.family<List<InventoryMovement>, String>((ref, itemId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('inventory_movements')
      .select()
      .eq('item_id', itemId)
      .order('performed_at', ascending: false)
      .limit(100);
  return (rows as List)
      .map((r) => InventoryMovement.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class InventoryRepo {
  InventoryRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  Future<InventoryItem> upsertItem({
    String? id,
    required String name,
    String? sku,
    String? description,
    String unit = 'piece',
    double unitCost = 0,
    double reorderThreshold = 0,
    String? categoryId,
    String? centerId,
    String? vendorId,
    bool isActive = true,
  }) async {
    final payload = <String, dynamic>{
      'academy_id': _academyId,
      'name': name,
      'sku': sku,
      'description': description,
      'unit': unit,
      'unit_cost': unitCost,
      'reorder_threshold': reorderThreshold,
      'category_id': categoryId,
      'center_id': centerId,
      'vendor_id': vendorId,
      'is_active': isActive,
    };
    final r = id == null
        ? await _client
            .from('inventory_items')
            .insert(payload)
            .select()
            .single()
        : await _client
            .from('inventory_items')
            .update(payload)
            .eq('id', id)
            .select()
            .single();
    return InventoryItem.fromMap(r);
  }

  Future<InventoryCategory> createCategory(String name, {String? description}) async {
    final r = await _client
        .from('inventory_categories')
        .insert({
          'academy_id': _academyId,
          'name': name,
          'description': description,
        })
        .select()
        .single();
    return InventoryCategory.fromMap(r);
  }

  Future<Vendor> upsertVendor({
    String? id,
    required String name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    String? notes,
    bool isActive = true,
  }) async {
    final payload = {
      'academy_id': _academyId,
      'name': name,
      'contact_name': contactName,
      'email': email,
      'phone': phone,
      'address': address,
      'notes': notes,
      'is_active': isActive,
    };
    final r = id == null
        ? await _client.from('vendors').insert(payload).select().single()
        : await _client
            .from('vendors')
            .update(payload)
            .eq('id', id)
            .select()
            .single();
    return Vendor.fromMap(r);
  }

  /// Records a movement; on_hand is updated server-side via trigger.
  Future<void> recordMovement({
    required String itemId,
    required String kind, // 'in' | 'out' | 'adjustment' | 'return'
    required double qty,
    String? studentId,
    String? coachId,
    String? vendorId,
    double? unitCost,
    String? reference,
    String? notes,
  }) async {
    // Sign convention enforced server-side; mirror it client-side so the
    // user picks a positive number and the kind decides the sign.
    final signedQty = (kind == 'out')
        ? -qty.abs()
        : (kind == 'adjustment' ? qty : qty.abs());

    await _client.from('inventory_movements').insert({
      'academy_id': _academyId,
      'item_id': itemId,
      'kind': kind,
      'qty': signedQty,
      'student_id': studentId,
      'coach_id': coachId,
      'vendor_id': vendorId,
      'unit_cost': unitCost,
      'reference': reference,
      'notes': notes,
    });
  }
}

final inventoryRepoProvider = FutureProvider<InventoryRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return InventoryRepo(
    ref.watch(supabaseClientProvider),
    profile!.academyId!,
  );
});
