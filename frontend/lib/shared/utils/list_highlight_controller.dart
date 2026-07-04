import 'package:flutter/widgets.dart';

/// manages scroll-to + temporary highlight behavior for a list item reached
/// via a deep link from another tab (e.g. "View in Appointments" on an estimate)
class ListHighlightController {
  ListHighlightController(String? initialId) : highlightedId = initialId;

  String? highlightedId;
  bool _hasScrolled = false;
  final Map<String, GlobalKey> _keys = {};

  GlobalKey keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  bool isHighlighted(String id) => highlightedId != null && highlightedId == id;

  /// call once per build with the currently loaded item ids; scrolls to and
  /// flashes the highlighted item the first time it appears in the list
  void maybeScrollTo(List<String> loadedIds, void Function() onSettle) {
    if (highlightedId == null || _hasScrolled || !loadedIds.contains(highlightedId)) {
      return;
    }
    _hasScrolled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemContext = _keys[highlightedId]?.currentContext;
      if (itemContext != null) {
        Scrollable.ensureVisible(
          itemContext,
          duration: const Duration(milliseconds: 400),
          alignment: 0.1,
        );
      }
      Future.delayed(const Duration(milliseconds: 2500), () {
        highlightedId = null;
        onSettle();
      });
    });
  }
}
