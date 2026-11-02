/// hands back the same stream for the same inputs across rebuilds.
///
/// A `StreamBuilder` whose `stream:` is created inside `build()` gets a new
/// stream on every `setState`, resubscribes, and drops back to
/// `ConnectionState.waiting` — so a list page swaps its whole body (search
/// box included) for a loading spinner on every keystroke, and the search
/// box loses focus after each character. Keep one of these on the page's
/// `State` and wrap each stream in [get].
class StreamCache {
  final _entries = <String, ({Object? key, Stream<dynamic> stream})>{};

  /// the cached stream in [slot], recreated via [create] only when [key]
  /// (e.g. the role/clientId the query depends on) changes
  Stream<T> get<T>(String slot, Object? key, Stream<T> Function() create) {
    final entry = _entries[slot];
    if (entry != null && entry.key == key) return entry.stream as Stream<T>;
    // a stable object that still calls [create] once per listener, so a
    // remounted StreamBuilder can re-listen (Firestore snapshot streams are
    // single-subscription and throw on a second listen)
    final stream = Stream<T>.multi((controller) {
      final subscription = create().listen(
        controller.addSync,
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      controller
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = subscription.cancel;
    });
    _entries[slot] = (key: key, stream: stream);
    return stream;
  }
}
