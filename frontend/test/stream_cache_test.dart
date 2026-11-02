import 'package:anchor/shared/utils/stream_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same key returns the same stream; it can be listened to twice', () async {
    final cache = StreamCache();
    var created = 0;
    Stream<int> make() {
      created++;
      return Stream.value(1); // single-subscription
    }

    final a = cache.get('s', ('owner', null), make);
    final b = cache.get('s', ('owner', null), make);
    expect(identical(a, b), isTrue);
    expect(await a.first, 1);
    expect(await a.first, 1); // re-listen doesn't throw
    expect(created, 2);

    final c = cache.get('s', ('client', 'x'), make);
    expect(identical(a, c), isFalse);
  });
}
