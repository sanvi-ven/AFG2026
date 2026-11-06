import 'package:flutter_test/flutter_test.dart';
import 'package:anchor/models/estimate.dart';
import 'package:anchor/models/fall_cleanup.dart';
import 'package:anchor/models/invoice.dart';

void main() {
  Estimate build(EstimateDiscount? discount) => Estimate(
        id: 'e',
        estimateNumber: 'EST-1',
        clientId: 'c',
        services: const [
          InvoiceServiceItem(name: 'Mow', price: 99.99),
          InvoiceServiceItem(name: 'Free check', price: 0),
        ],
        total: 0,
        status: 'pending',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        convertedToInvoice: false,
        discount: discount,
      );

  test('percent discount rounds to the cent and adds a negative line', () {
    final e = build(const EstimateDiscount(type: 'percent', value: 15));
    expect(e.discountAmount, 15.0);
    expect(e.billableServices.last.price, -15.0);
    expect(e.billableServices.last.name, 'Discount (15%)');
    final sum = e.billableServices.fold<double>(0, (s, i) => s + i.price);
    expect(sum, closeTo(84.99, 0.001));
  });

  test('flat discount is capped at the subtotal', () {
    final e = build(const EstimateDiscount(type: 'flat', value: 500));
    expect(e.discountAmount, 99.99);
  });

  test('no discount leaves services untouched', () {
    expect(build(null).billableServices.length, 2);
  });

  test('discount round-trips through toMap/fromMap', () {
    final e = build(const EstimateDiscount(type: 'percent', value: 12.5));
    final back = Estimate.fromMap(e.toMap());
    expect(back.discount?.label, 'Discount (12.5%)');
  });

  Map<String, dynamic> fallCleanupDoc(Map<String, dynamic>? selection) => {
        'id': 'f',
        'type': EstimateType.fallCleanup,
        'services': [
          {'name': 'Extra pile', 'price': 50},
        ],
        'total': 999, // stale on purpose: a fall cleanup total is derived
        'fallCleanup': {
          'packagePrices': {'essential': 300, 'premium': 450, 'both': 700},
          'disposalPrices': {'woods_curb': 0, 'bag_leave': 40, 'haul_away': 100},
          'extraPrices': <String, dynamic>{},
          if (selection != null) 'selection': selection,
        },
        'discount': {'type': 'percent', 'value': 10},
      };

  test('fall cleanup discount follows the client\'s pick', () {
    final e = Estimate.fromMap(fallCleanupDoc(
        {'package': 'premium', 'disposal': 'haul_away', 'extras': []}));
    expect(e.subtotal, 600); // 450 + 100 + 50 additional work
    expect(e.discountAmount, 60);
    expect(e.total, 540);
    final lines = e.billableServices;
    expect(lines.last.price, -60);
    expect(lines.fold<double>(0, (s, i) => s + i.price), 540);
  });

  test('fall cleanup with no package keeps its discount for later', () {
    final e = Estimate.fromMap(fallCleanupDoc(null));
    expect(e.discount?.offText, '10% off');
  });
}
