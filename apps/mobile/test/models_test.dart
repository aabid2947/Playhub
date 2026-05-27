import 'package:flutter_test/flutter_test.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/inventory/data/inventory.dart';

// Pure model logic: enum fallbacks, fromMap parsing, derived getters/math.
// No device or network needed.
void main() {
  group('enum fromDb fallbacks', () {
    test('FeeType', () {
      expect(FeeType.fromDb('quarterly'), FeeType.quarterly);
      expect(FeeType.fromDb(null), FeeType.monthly);
      expect(FeeType.fromDb('garbage'), FeeType.monthly);
    });
    test('InvoiceStatus', () {
      expect(InvoiceStatus.fromDb('paid'), InvoiceStatus.paid);
      expect(InvoiceStatus.fromDb(null), InvoiceStatus.issued);
      expect(InvoiceStatus.fromDb('???'), InvoiceStatus.issued);
    });
    test('DiscountType', () {
      expect(DiscountType.fromDb('flat'), DiscountType.flat);
      expect(DiscountType.fromDb(null), DiscountType.percentage);
    });
  });

  group('FeeStructure', () {
    FeeStructure parse(num base, num tax) => FeeStructure.fromMap({
          'id': '1',
          'academy_id': 'a',
          'name': 'Monthly',
          'type': 'monthly',
          'base_amount': base,
          'tax_pct': tax,
        });

    test('totalAmount adds tax', () {
      expect(parse(1000, 18).totalAmount, 1180);
      expect(parse(2000, 0).totalAmount, 2000);
    });
    test('fromMap defaults late-fee fields', () {
      final f = parse(1000, 0);
      expect(f.lateFeeGraceDays, 5);
      expect(f.lateFeePolicy, 'one_time');
      expect(f.isActive, isTrue);
      expect(f.lateFeePct, isNull);
    });
  });

  group('Invoice', () {
    Invoice parse({num amount = 2000, num paid = 0, Object? discount}) =>
        Invoice.fromMap({
          'id': '1',
          'academy_id': 'a',
          'student_id': 's',
          'invoice_number': 'INV-1',
          'status': 'issued',
          'due_date': '2026-01-31',
          'issued_at': '2026-01-01T00:00:00Z',
          'base_amount': amount,
          'tax_amount': 0,
          'late_fee_amount': 0,
          if (discount != null) 'discount_amount': discount,
          'amount': amount,
          'amount_paid': paid,
        });

    test('balance is amount minus amountPaid', () {
      expect(parse(paid: 500).balance, 1500);
      expect(parse(paid: 2000).balance, 0);
    });
    test('discountAmount defaults to 0 when absent', () {
      expect(parse().discountAmount, 0);
      expect(parse(discount: 250).discountAmount, 250);
    });
  });

  group('DiscountStructure.summary', () {
    DiscountStructure d(String type, num value) => DiscountStructure.fromMap({
          'id': '1',
          'academy_id': 'a',
          'name': 'X',
          'type': type,
          'value': value,
        });

    test('percentage drops the decimal only when whole', () {
      expect(d('percentage', 25).summary, '25%');
      expect(d('percentage', 25.5).summary, '25.5%');
    });
    test('flat renders rupees with no decimals', () {
      expect(d('flat', 500).summary, '₹500');
    });
  });

  group('BatchSchedule', () {
    test('summary handles empty / days-only / days+times', () {
      expect(const BatchSchedule().summary, 'No schedule');
      expect(const BatchSchedule(days: ['mon', 'wed']).summary, 'mon, wed');
      expect(
        const BatchSchedule(days: ['mon'], startTime: '16:00').summary,
        'mon  16:00',
      );
      expect(
        const BatchSchedule(days: ['mon'], startTime: '16:00', endTime: '17:30').summary,
        'mon  16:00–17:30',
      );
    });
    test('toMap omits null times and round-trips through fromMap', () {
      const s = BatchSchedule(days: ['tue', 'thu'], startTime: '07:00', endTime: '08:30');
      final map = s.toMap();
      expect(map.containsKey('start_time'), isTrue);
      final back = BatchSchedule.fromMap(map);
      expect(back.days, s.days);
      expect(back.startTime, '07:00');
      expect(back.endTime, '08:30');

      const noTimes = BatchSchedule(days: ['mon']);
      expect(noTimes.toMap().containsKey('start_time'), isFalse);
    });
  });

  group('InventoryItem.lowStock', () {
    InventoryItem item({required double onHand, required double threshold}) =>
        InventoryItem(
          id: '1', name: 'Bat', unit: 'piece', unitCost: 0,
          onHand: onHand, reorderThreshold: threshold, isActive: true,
        );

    test('true only when threshold > 0 and on_hand <= threshold', () {
      expect(item(onHand: 17, threshold: 25).lowStock, isTrue);
      expect(item(onHand: 30, threshold: 10).lowStock, isFalse);
      expect(item(onHand: 25, threshold: 25).lowStock, isTrue); // boundary
      expect(item(onHand: 0, threshold: 0).lowStock, isFalse); // threshold off
    });
  });
}
