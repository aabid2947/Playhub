class InventoryCategory {
  const InventoryCategory({
    required this.id,
    required this.name,
    this.description,
  });

  factory InventoryCategory.fromMap(Map<String, dynamic> m) =>
      InventoryCategory(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
      );

  final String id;
  final String name;
  final String? description;
}

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.isActive,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.notes,
  });

  factory Vendor.fromMap(Map<String, dynamic> m) => Vendor(
        id: m['id'] as String,
        name: m['name'] as String,
        contactName: m['contact_name'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        address: m['address'] as String?,
        notes: m['notes'] as String?,
        isActive: m['is_active'] as bool? ?? true,
      );

  final String id;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.unitCost,
    required this.onHand,
    required this.reorderThreshold,
    required this.isActive,
    this.sku,
    this.description,
    this.categoryId,
    this.centerId,
    this.vendorId,
  });

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
        id: m['id'] as String,
        sku: m['sku'] as String?,
        name: m['name'] as String,
        description: m['description'] as String?,
        unit: m['unit'] as String? ?? 'piece',
        unitCost: (m['unit_cost'] as num?)?.toDouble() ?? 0.0,
        onHand: (m['on_hand'] as num?)?.toDouble() ?? 0.0,
        reorderThreshold:
            (m['reorder_threshold'] as num?)?.toDouble() ?? 0.0,
        categoryId: m['category_id'] as String?,
        centerId: m['center_id'] as String?,
        vendorId: m['vendor_id'] as String?,
        isActive: m['is_active'] as bool? ?? true,
      );

  final String id;
  final String? sku;
  final String name;
  final String? description;
  final String unit;
  final double unitCost;
  final double onHand;
  final double reorderThreshold;
  final String? categoryId;
  final String? centerId;
  final String? vendorId;
  final bool isActive;

  bool get lowStock => reorderThreshold > 0 && onHand <= reorderThreshold;
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.qty,
    required this.performedAt,
    this.studentId,
    this.coachId,
    this.vendorId,
    this.unitCost,
    this.reference,
    this.notes,
    this.performedBy,
  });

  factory InventoryMovement.fromMap(Map<String, dynamic> m) =>
      InventoryMovement(
        id: m['id'] as String,
        itemId: m['item_id'] as String,
        kind: m['kind'] as String,
        qty: (m['qty'] as num).toDouble(),
        studentId: m['student_id'] as String?,
        coachId: m['coach_id'] as String?,
        vendorId: m['vendor_id'] as String?,
        unitCost: (m['unit_cost'] as num?)?.toDouble(),
        reference: m['reference'] as String?,
        notes: m['notes'] as String?,
        performedBy: m['performed_by'] as String?,
        performedAt:
            DateTime.parse(m['performed_at'] as String).toLocal(),
      );

  final String id;
  final String itemId;
  final String kind;
  final double qty;
  final String? studentId;
  final String? coachId;
  final String? vendorId;
  final double? unitCost;
  final String? reference;
  final String? notes;
  final String? performedBy;
  final DateTime performedAt;
}
