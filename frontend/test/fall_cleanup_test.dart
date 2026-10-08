import 'package:anchor/models/estimate.dart';
import 'package:flutter_test/flutter_test.dart';

Estimate _fallCleanup(Map<String, dynamic> selection,
    {List<Map<String, dynamic>> additionalWork = const []}) {
  return Estimate.fromMap({
    'id': 'e1',
    'estimateNumber': 'EST-0001',
    'clientId': 'c1',
    'type': 'fall_cleanup',
    'services': additionalWork,
    // a stale stored total must be ignored for fall cleanup estimates
    'total': 9999,
    'fallCleanup': {
      'packagePrices': {'essential': 200, 'premium': 300, 'both': 400},
      'disposalPrices': {'woods_curb': 0, 'bag_leave': 50, 'haul_away': 75},
      'extraPrices': {
        'gutter_cleaning': 200,
        'aeration_overseeding': null,
        'hardscape_weed_removal': 75,
        'asap_service': 35,
      },
      'selection': selection,
    },
  });
}

void main() {
  test('total = selected package + disposal + checked extras + additional work',
      () {
    final estimate = _fallCleanup(
      {
        'package': 'premium',
        'disposal': 'woods_curb',
        'extras': ['gutter_cleaning']
      },
      additionalWork: [
        {'name': 'Hedge trim', 'price': 120},
      ],
    );
    expect(estimate.isFallCleanup, isTrue);
    expect(estimate.total, 620);
    expect(estimate.fallCleanup!.hasUponRequestSelected, isFalse);
    expect(estimate.billableServices.map((item) => item.price),
        [300, 0, 200, 120]);
  });

  test('nothing selected works as a menu with no total', () {
    final estimate =
        _fallCleanup({'package': null, 'disposal': null, 'extras': []});
    expect(estimate.fallCleanup!.hasPackage, isFalse);
    expect(estimate.total, 0);
  });

  test('a selected Upon Request item is flagged and left out of the sum', () {
    final estimate = _fallCleanup({
      'package': 'both',
      'disposal': 'haul_away',
      'extras': ['aeration_overseeding'],
    });
    expect(estimate.total, 475);
    expect(estimate.fallCleanup!.hasUponRequestSelected, isTrue);
    expect(estimate.fallCleanup!.isTwoVisit, isTrue);
  });

  test('a standard estimate keeps its stored total and services', () {
    final estimate = Estimate.fromMap({
      'id': 'e2',
      'services': [
        {'name': 'Mow', 'price': 50},
      ],
      'total': 50,
    });
    expect(estimate.isFallCleanup, isFalse);
    expect(estimate.billableServices.single.name, 'Mow');
  });
}
