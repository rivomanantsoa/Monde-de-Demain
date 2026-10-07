import 'package:flutter_application_1/bookmarks/bookmarks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('marks are stored per item, can be moved, undone and removed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BookmarkStore(await SharedPreferences.getInstance());
    var notified = 0;
    store.addListener(() => notified++);

    expect(store.get('fr/b/a'), isNull);
    store.set('fr/b/a', 12, 340);
    store.set('fr/k/cours/01', 3, 0);
    expect(store.get('fr/b/a')!.anchor, (12, 340));
    expect(store.get('fr/k/cours/01')!.anchor, (3, 0));

    final before = store.get('fr/b/a');
    store.set('fr/b/a', 20, 0); // move
    store.restore('fr/b/a', before); // undo
    expect(store.get('fr/b/a')!.anchor, (12, 340));

    store.remove('fr/b/a');
    expect(store.has('fr/b/a'), isFalse);
    expect(store.has('fr/k/cours/01'), isTrue);
    expect(notified, 5);
  });

  test('isIn matches the fragment that holds the mark', () {
    final m = ReadingMark(block: 4, char: 120, at: DateTime(2026));
    expect(m.isIn(4, 0, 100), isFalse);
    expect(m.isIn(4, 100, 50), isTrue);
    expect(m.isIn(5, 100, 50), isFalse);
    expect(ReadingMark.decode(m.encode())!.anchor, (4, 120));
    expect(ReadingMark.decode('garbage'), isNull);
  });
}
