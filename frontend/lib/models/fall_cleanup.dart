import 'invoice.dart';

/// one fixed, season-config option on a fall cleanup estimate (a package,
/// a leaf disposal choice, or an optional extra). Names/descriptions are the
/// 2026 Fall Cleanup Policy's own copy, stored once here rather than per
/// estimate; only the price is set per estimate.
class FallCleanupOption {
  const FallCleanupOption({
    required this.key,
    required this.name,
    required this.description,
    this.defaultPrice,
  });

  final String key;
  final String name;
  final String description;

  /// prefilled into a new estimate's price field; null leaves it blank
  /// (which prints as "Upon Request")
  final double? defaultPrice;
}

/// the fall cleanup season config: every option, in the fixed order the
/// estimate always prints them.
class FallCleanupCatalog {
  FallCleanupCatalog._();

  static const packages = <FallCleanupOption>[
    FallCleanupOption(
      key: 'essential',
      name: 'Essential',
      description:
          'A single pass with blowers across primary lawn areas and garden beds. '
          'A small amount of stray leaf debris may remain in low-visibility beds '
          'or sections of the lawn. Walkways, steps, and driveway will be cleared '
          'of leaves as well.',
    ),
    FallCleanupOption(
      key: 'premium',
      name: 'Premium',
      description:
          'A full-service cleanup. We rake and vacuum garden beds, clear all hard '
          'surfaces and lawn areas, and perform a final detailed cleanup pass. '
          'Includes a final lawn cut at the proper height to prevent winter mold '
          'and encourage healthy spring growth, along with string trimming, edge '
          'detailing, and blowing off all hardscapes.',
    ),
    FallCleanupOption(
      key: 'both',
      name: 'Both (Two Visits)',
      description:
          'Designed for properties with late-dropping trees like oaks. The first '
          'visit in late October provides essential maintenance to keep the '
          'property tidy. The second visit in late autumn is a full premium '
          'cleanup to prepare your lawn for winter.',
    ),
  ];

  static const disposals = <FallCleanupOption>[
    FallCleanupOption(
      key: 'woods_curb',
      name: 'Blow to Woods or Curb',
      description:
          'Included in base pricing (where allowed by local ordinance).',
      defaultPrice: 0,
    ),
    FallCleanupOption(
      key: 'bag_leave',
      name: 'Bag & Leave On-Site',
      description:
          'Leaves are bagged and left at designated areas on your property.',
      defaultPrice: 50,
    ),
    FallCleanupOption(
      key: 'haul_away',
      name: 'Full Haul-Away',
      description: 'We remove all leaf debris from the property.',
      defaultPrice: 75,
    ),
  ];

  static const extras = <FallCleanupOption>[
    FallCleanupOption(
      key: 'gutter_cleaning',
      name: 'Gutter Cleaning',
      description:
          'Remove all leaves and debris from gutters to ensure proper drainage '
          'throughout the winter.',
    ),
    FallCleanupOption(
      key: 'aeration_overseeding',
      name: 'Aeration & Overseeding',
      description:
          'Poke small holes in the lawn to loosen soil and plant new seed for a '
          'healthy lawn in the spring.',
    ),
    FallCleanupOption(
      key: 'hardscape_weed_removal',
      name: 'Hardscape Weed Removal',
      description:
          'Remove weeds and grass from cracks in hardscapes such as driveways, '
          'patios, and walkways. After removal, torch the dirt to kill roots and '
          'slow regrowth.',
    ),
    FallCleanupOption(
      key: 'asap_service',
      name: 'ASAP Service',
      description:
          'If booking late in the season, paying this additional fee will have '
          'our team work overtime in order to fit in your cleanup as soon as '
          'possible.',
    ),
  ];

  /// the package key whose total is billed 50% after each of two visits
  static const twoVisitPackageKey = 'both';

  static const policyUrl = 'rplandscaping.org/fall2026policy';

  /// default Terms for a new fall cleanup estimate, from the Fall Cleanup
  /// Policy (the standard estimate's own default is untouched). Editable per
  /// estimate like any other Terms text.
  static String defaultTerms(String companyName) {
    final business =
        companyName.trim().isEmpty ? 'our' : 'the ${companyName.trim()}';
    return 'Payment is due upon completion of service. For two-visit packages, '
        '50% is billed after each visit. Invoices unpaid after 72 hours incur a '
        'one-time 10% late fee. By approving this estimate, you agree to '
        '$business Fall Cleanup Policy (2026), which is provided with this '
        'estimate and can also be found at $policyUrl.';
  }

  static FallCleanupOption? find(List<FallCleanupOption> options, String? key) {
    for (final option in options) {
      if (option.key == key) return option;
    }
    return null;
  }
}

/// what the client picked (or the owner pre-selected): at most one package,
/// at most one disposal choice, any number of extras. Kept in its own map so
/// Firestore rules can let a client write only this part on approval, never
/// the prices.
class FallCleanupSelection {
  const FallCleanupSelection({
    this.package,
    this.disposal,
    this.extras = const <String>[],
  });

  final String? package;
  final String? disposal;
  final List<String> extras;

  factory FallCleanupSelection.fromMap(Map<String, dynamic> map) {
    String? readKey(dynamic value) {
      final key = (value as String?)?.trim() ?? '';
      return key.isEmpty ? null : key;
    }

    return FallCleanupSelection(
      package: readKey(map['package']),
      disposal: readKey(map['disposal']),
      extras: (map['extras'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'package': package,
        'disposal': disposal,
        'extras': extras,
      };
}

/// one selected item as it prints in the total breakdown and becomes an
/// invoice line item
class FallCleanupLine {
  const FallCleanupLine({
    required this.category,
    required this.option,
    required this.price,
  });

  /// 'Package', 'Disposal', or 'Extra'
  final String category;
  final FallCleanupOption option;

  /// null means Upon Request
  final double? price;
}

/// the fall cleanup portion of an Estimate (estimate.type == 'fall_cleanup').
/// Additional work, notes, and terms reuse the standard Estimate fields.
class FallCleanupDetails {
  const FallCleanupDetails({
    required this.packagePrices,
    required this.disposalPrices,
    required this.extraPrices,
    this.selection = const FallCleanupSelection(),
  });

  /// option key -> price; a null (or missing) price means Upon Request
  final Map<String, double?> packagePrices;
  final Map<String, double?> disposalPrices;
  final Map<String, double?> extraPrices;
  final FallCleanupSelection selection;

  /// a new estimate: season default prices, nothing selected
  factory FallCleanupDetails.defaults() {
    Map<String, double?> defaultsFor(List<FallCleanupOption> options) => {
          for (final option in options) option.key: option.defaultPrice,
        };
    return FallCleanupDetails(
      packagePrices: defaultsFor(FallCleanupCatalog.packages),
      disposalPrices: defaultsFor(FallCleanupCatalog.disposals),
      extraPrices: defaultsFor(FallCleanupCatalog.extras),
    );
  }

  factory FallCleanupDetails.fromMap(Map<String, dynamic> map) {
    Map<String, double?> readPrices(dynamic value) {
      if (value is! Map) return <String, double?>{};
      return value.map((key, price) =>
          MapEntry(key.toString(), (price as num?)?.toDouble()));
    }

    final selection = map['selection'];
    return FallCleanupDetails(
      packagePrices: readPrices(map['packagePrices']),
      disposalPrices: readPrices(map['disposalPrices']),
      extraPrices: readPrices(map['extraPrices']),
      selection: selection is Map
          ? FallCleanupSelection.fromMap(
              selection.map((key, value) => MapEntry(key.toString(), value)))
          : const FallCleanupSelection(),
    );
  }

  Map<String, dynamic> toMap() => {
        'packagePrices': packagePrices,
        'disposalPrices': disposalPrices,
        'extraPrices': extraPrices,
        'selection': selection.toMap(),
      };

  FallCleanupDetails copyWith({FallCleanupSelection? selection}) {
    return FallCleanupDetails(
      packagePrices: packagePrices,
      disposalPrices: disposalPrices,
      extraPrices: extraPrices,
      selection: selection ?? this.selection,
    );
  }

  bool get hasPackage =>
      FallCleanupCatalog.find(FallCleanupCatalog.packages, selection.package) !=
      null;

  bool get isTwoVisit =>
      selection.package == FallCleanupCatalog.twoVisitPackageKey;

  /// selected items in print order: package, disposal, then checked extras
  List<FallCleanupLine> get selectedLines {
    final lines = <FallCleanupLine>[];
    final package =
        FallCleanupCatalog.find(FallCleanupCatalog.packages, selection.package);
    if (package != null) {
      lines.add(FallCleanupLine(
          category: 'Package',
          option: package,
          price: packagePrices[package.key]));
    }
    final disposal = FallCleanupCatalog.find(
        FallCleanupCatalog.disposals, selection.disposal);
    if (disposal != null) {
      lines.add(FallCleanupLine(
          category: 'Disposal',
          option: disposal,
          price: disposalPrices[disposal.key]));
    }
    for (final extra in FallCleanupCatalog.extras) {
      if (selection.extras.contains(extra.key)) {
        lines.add(FallCleanupLine(
            category: 'Extra', option: extra, price: extraPrices[extra.key]));
      }
    }
    return lines;
  }

  /// true when any selected item has no price yet (prints "+ items upon
  /// request" after the known sum)
  bool get hasUponRequestSelected =>
      selectedLines.any((line) => line.price == null);

  /// selected package + disposal + checked extras + additional work rows,
  /// counting only items that have a price
  double knownTotal(List<InvoiceServiceItem> additionalWork) {
    final selectedSum =
        selectedLines.fold<double>(0, (sum, line) => sum + (line.price ?? 0));
    return additionalWork.fold<double>(
        selectedSum, (sum, item) => sum + item.price);
  }

  /// invoice/job line items for everything selected, followed by the
  /// additional work rows. Upon Request items are skipped (they have no
  /// price to bill); callers that bill should block on
  /// [hasUponRequestSelected] first.
  List<InvoiceServiceItem> billableItems(
      List<InvoiceServiceItem> additionalWork) {
    return [
      for (final line in selectedLines)
        if (line.price != null)
          InvoiceServiceItem(
            name: switch (line.category) {
              'Package' => 'Fall Cleanup: ${line.option.name}',
              'Disposal' => 'Leaf Disposal: ${line.option.name}',
              _ => line.option.name,
            },
            description: line.option.description,
            price: line.price!,
          ),
      ...additionalWork,
    ];
  }
}

/// estimate.type values; a missing type means [standard]
class EstimateType {
  EstimateType._();

  static const standard = 'standard';
  static const fallCleanup = 'fall_cleanup';
}
