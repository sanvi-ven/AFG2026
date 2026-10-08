/// UI pieces for the Fall Cleanup estimate template on the Estimates page:
/// the owner's price/selection editor, the in-app summary shown on an
/// estimate card, and the package/disposal/extras chooser used when the
/// estimate is approved.
library;

import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../models/fall_cleanup.dart';
import '../../../models/invoice.dart';
import '../../../models/legal_document.dart';

String _formatPrice(double? price, {bool zeroIsIncluded = false}) {
  if (price == null) return 'Upon Request';
  if (zeroIsIncluded && price == 0) return 'Included';
  return '\$${price.toStringAsFixed(2)}';
}

/// owner-side form state for a fall cleanup estimate: one price field per
/// option (blank = Upon Request) plus the current selection
class FallCleanupFormController extends ChangeNotifier {
  FallCleanupFormController([FallCleanupDetails? initial]) {
    final details = initial ?? FallCleanupDetails.defaults();
    String text(double? price) => price == null ? '' : price.toStringAsFixed(2);
    for (final option in FallCleanupCatalog.packages) {
      packagePrices[option.key] =
          TextEditingController(text: text(details.packagePrices[option.key]));
    }
    for (final option in FallCleanupCatalog.disposals) {
      disposalPrices[option.key] =
          TextEditingController(text: text(details.disposalPrices[option.key]));
    }
    for (final option in FallCleanupCatalog.extras) {
      extraPrices[option.key] =
          TextEditingController(text: text(details.extraPrices[option.key]));
    }
    package = details.selection.package;
    disposal = details.selection.disposal;
    extras = details.selection.extras.toSet();
  }

  final Map<String, TextEditingController> packagePrices = {};
  final Map<String, TextEditingController> disposalPrices = {};
  final Map<String, TextEditingController> extraPrices = {};
  String? package;
  String? disposal;
  Set<String> extras = {};

  /// back to season defaults, nothing selected (after an estimate is sent)
  void reset() {
    final fresh = FallCleanupFormController();
    void copy(Map<String, TextEditingController> to,
        Map<String, TextEditingController> from) {
      from.forEach((key, controller) => to[key]!.text = controller.text);
    }

    copy(packagePrices, fresh.packagePrices);
    copy(disposalPrices, fresh.disposalPrices);
    copy(extraPrices, fresh.extraPrices);
    package = null;
    disposal = null;
    extras = {};
    fresh.dispose();
    notifyListeners();
  }

  /// every price field plus this controller's own selection changes, so a
  /// live total can rebuild on any edit
  Listenable get changes => Listenable.merge([
        this,
        ...packagePrices.values,
        ...disposalPrices.values,
        ...extraPrices.values,
      ]);

  /// the editor calls this after changing [package]/[disposal]/[extras]
  void selectionChanged() => notifyListeners();

  /// the details as typed so far, for a live total: an unparseable price is
  /// treated like a blank one (Upon Request) instead of failing
  FallCleanupDetails liveDetails() {
    Map<String, double?> read(Map<String, TextEditingController> fields) => {
          for (final entry in fields.entries)
            entry.key: double.tryParse(
                entry.value.text.trim().replaceAll(r'$', '')),
        };
    return FallCleanupDetails(
      packagePrices: read(packagePrices),
      disposalPrices: read(disposalPrices),
      extraPrices: read(extraPrices),
      selection: FallCleanupSelection(
        package: package,
        disposal: disposal,
        extras: extras.toList(),
      ),
    );
  }

  /// the entered details, or null with [error] set when a price isn't a
  /// valid non-negative number
  FallCleanupDetails? toDetails({void Function(String error)? onError}) {
    Map<String, double?>? read(List<FallCleanupOption> options,
        Map<String, TextEditingController> fields) {
      final prices = <String, double?>{};
      for (final option in options) {
        final raw = fields[option.key]!.text.trim().replaceAll(r'$', '');
        if (raw.isEmpty) {
          prices[option.key] = null;
          continue;
        }
        final value = double.tryParse(raw);
        if (value == null || value < 0) {
          onError?.call(
              '${option.name}: enter a price, or leave it blank for "Upon Request".');
          return null;
        }
        prices[option.key] = value;
      }
      return prices;
    }

    final packages = read(FallCleanupCatalog.packages, packagePrices);
    if (packages == null) return null;
    final disposals = read(FallCleanupCatalog.disposals, disposalPrices);
    if (disposals == null) return null;
    final extraMap = read(FallCleanupCatalog.extras, extraPrices);
    if (extraMap == null) return null;

    return FallCleanupDetails(
      packagePrices: packages,
      disposalPrices: disposals,
      extraPrices: extraMap,
      selection: FallCleanupSelection(
        package: package,
        disposal: disposal,
        extras: [
          for (final option in FallCleanupCatalog.extras)
            if (extras.contains(option.key)) option.key,
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      ...packagePrices.values,
      ...disposalPrices.values,
      ...extraPrices.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}

/// owner editor: every package, disposal choice, and extra with its price
/// field, plus the (optional) pre-selection. Leaving a package/disposal
/// unselected sends the estimate as a menu the client chooses from.
class FallCleanupEditor extends StatefulWidget {
  const FallCleanupEditor({required this.controller, super.key});

  final FallCleanupFormController controller;

  @override
  State<FallCleanupEditor> createState() => _FallCleanupEditorState();
}

class _FallCleanupEditorState extends State<FallCleanupEditor> {
  FallCleanupFormController get _c => widget.controller;

  Widget _row({
    required FallCleanupOption option,
    required bool selected,
    required ValueChanged<bool> onSelected,
    required TextEditingController priceController,
    String? zeroHint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) {
              setState(() => onSelected(value ?? false));
              _c.selectionChanged();
            },
          ),
          Expanded(
            child: Tooltip(
              message: option.description,
              child: Text(option.name),
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                prefixText: '\$',
                hintText: 'Upon Request',
                helperText: zeroHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(hint,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tick what the client already chose, or leave a group unticked to send it as a menu. '
          'A blank price prints "Upon Request".',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _heading(context, 'Cleanup Package', 'Choose one'),
        for (final option in FallCleanupCatalog.packages)
          _row(
            option: option,
            selected: _c.package == option.key,
            onSelected: (value) => _c.package = value ? option.key : null,
            priceController: _c.packagePrices[option.key]!,
          ),
        _heading(context, 'Leaf Removal & Disposal', 'Choose one'),
        for (final option in FallCleanupCatalog.disposals)
          _row(
            option: option,
            selected: _c.disposal == option.key,
            onSelected: (value) => _c.disposal = value ? option.key : null,
            priceController: _c.disposalPrices[option.key]!,
            zeroHint: option.defaultPrice == 0 ? '\$0 prints "Included"' : null,
          ),
        _heading(context, 'Optional Extras', 'Add any'),
        for (final option in FallCleanupCatalog.extras)
          _row(
            option: option,
            selected: _c.extras.contains(option.key),
            onSelected: (value) => value
                ? _c.extras.add(option.key)
                : _c.extras.remove(option.key),
            priceController: _c.extraPrices[option.key]!,
          ),
      ],
    );
  }
}

/// read-only in-app view of a fall cleanup estimate on its card: every
/// option with its price (selected ones marked), additional work, and the
/// total per the template's rules
class FallCleanupSummary extends StatelessWidget {
  const FallCleanupSummary({
    required this.details,
    required this.additionalWork,
    required this.total,
    super.key,
  });

  final FallCleanupDetails details;
  final List<InvoiceServiceItem> additionalWork;
  final double total;

  Widget _option(BuildContext context,
      {required FallCleanupOption option,
      required double? price,
      required bool selected,
      bool zeroIsIncluded = false}) {
    final color = selected ? Theme.of(context).colorScheme.primary : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: color ?? Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: option.description,
              child: Text(option.name,
                  style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : null,
                      color: color)),
            ),
          ),
          Text(_formatPrice(price, zeroIsIncluded: zeroIsIncluded),
              style: TextStyle(fontWeight: selected ? FontWeight.w700 : null)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final lines = details.selectedLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cleanup Package', style: titleStyle),
        const SizedBox(height: 6),
        for (final option in FallCleanupCatalog.packages)
          _option(context,
              option: option,
              price: details.packagePrices[option.key],
              selected: details.selection.package == option.key),
        const SizedBox(height: 8),
        Text('Leaf Removal & Disposal', style: titleStyle),
        const SizedBox(height: 6),
        for (final option in FallCleanupCatalog.disposals)
          _option(context,
              option: option,
              price: details.disposalPrices[option.key],
              selected: details.selection.disposal == option.key,
              zeroIsIncluded: true),
        const SizedBox(height: 8),
        Text('Optional Extras', style: titleStyle),
        const SizedBox(height: 6),
        for (final option in FallCleanupCatalog.extras)
          _option(context,
              option: option,
              price: details.extraPrices[option.key],
              selected: details.selection.extras.contains(option.key)),
        if (additionalWork.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Additional Work', style: titleStyle),
          const SizedBox(height: 6),
          for (final item in additionalWork)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.name)),
                      Text('\$${item.price.toStringAsFixed(2)}'),
                    ],
                  ),
                  if (item.description.isNotEmpty)
                    Text(item.description,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
        const Divider(height: 16),
        if (!details.hasPackage)
          const Text('Your total depends on the options you choose.',
              style: TextStyle(fontStyle: FontStyle.italic))
        else ...[
          for (final line in lines)
            Row(
              children: [
                Expanded(child: Text('${line.category}: ${line.option.name}')),
                Text(_formatPrice(line.price,
                    zeroIsIncluded: line.category == 'Disposal')),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(
                  child: Text('Total',
                      style: TextStyle(fontWeight: FontWeight.w700))),
              Text(
                '\$${total.toStringAsFixed(2)}'
                '${details.hasUponRequestSelected ? ' + items upon request' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (details.isTwoVisit)
            Text('Billed 50% after each visit.',
                style: Theme.of(context).textTheme.bodySmall),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.pushNamed(
              context,
              AppRouter.legalDocument,
              arguments: {'documentId': LegalDocumentIds.fallCleanupPolicy},
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('View Fall Cleanup Policy'),
          ),
        ),
      ],
    );
  }
}

/// pick (or confirm) the package, disposal, and extras when a fall cleanup
/// estimate is approved — by the client in-app, or by the owner recording a
/// phone/text approval. A package and a disposal choice are required, since
/// the policy's confirmation fields need both. Returns null on cancel.
Future<FallCleanupSelection?> showFallCleanupSelectionDialog(
  BuildContext context, {
  required FallCleanupDetails details,
  required String confirmLabel,
}) {
  return showDialog<FallCleanupSelection>(
    context: context,
    builder: (_) => _FallCleanupSelectionDialog(
        details: details, confirmLabel: confirmLabel),
  );
}

class _FallCleanupSelectionDialog extends StatefulWidget {
  const _FallCleanupSelectionDialog(
      {required this.details, required this.confirmLabel});

  final FallCleanupDetails details;
  final String confirmLabel;

  @override
  State<_FallCleanupSelectionDialog> createState() =>
      _FallCleanupSelectionDialogState();
}

class _FallCleanupSelectionDialogState
    extends State<_FallCleanupSelectionDialog> {
  late String? _package = widget.details.selection.package;
  late String? _disposal = widget.details.selection.disposal;
  late final Set<String> _extras = widget.details.selection.extras.toSet();

  Widget _choice({
    required FallCleanupOption option,
    required double? price,
    required bool selected,
    required ValueChanged<bool> onChanged,
    bool zeroIsIncluded = false,
  }) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      onChanged: (value) => setState(() => onChanged(value ?? false)),
      title: Row(
        children: [
          Expanded(
              child: Text(option.name,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(_formatPrice(price, zeroIsIncluded: zeroIsIncluded)),
        ],
      ),
      subtitle: Text(option.description),
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final canConfirm = _package != null && _disposal != null;
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    return AlertDialog(
      title: const Text('Choose your fall cleanup'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cleanup Package (choose one)', style: titleStyle),
              for (final option in FallCleanupCatalog.packages)
                _choice(
                  option: option,
                  price: details.packagePrices[option.key],
                  selected: _package == option.key,
                  onChanged: (value) => _package = value ? option.key : null,
                ),
              const SizedBox(height: 8),
              Text('Leaf Removal & Disposal (choose one)', style: titleStyle),
              for (final option in FallCleanupCatalog.disposals)
                _choice(
                  option: option,
                  price: details.disposalPrices[option.key],
                  selected: _disposal == option.key,
                  onChanged: (value) => _disposal = value ? option.key : null,
                  zeroIsIncluded: true,
                ),
              const SizedBox(height: 8),
              Text('Optional Extras (add any)', style: titleStyle),
              for (final option in FallCleanupCatalog.extras)
                _choice(
                  option: option,
                  price: details.extraPrices[option.key],
                  selected: _extras.contains(option.key),
                  onChanged: (value) => value
                      ? _extras.add(option.key)
                      : _extras.remove(option.key),
                ),
              if (!canConfirm)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Pick a package and a leaf disposal option to continue.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(FallCleanupSelection(
                    package: _package,
                    disposal: _disposal,
                    extras: [
                      for (final option in FallCleanupCatalog.extras)
                        if (_extras.contains(option.key)) option.key,
                    ],
                  ))
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
