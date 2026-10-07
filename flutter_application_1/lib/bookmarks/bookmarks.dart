import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Where I stopped reading" mark, one per readable item (brochure, course
/// lesson, or any future reader). The position is a text anchor — block
/// index + character offset — so it stays correct in page or scroll mode and
/// after the text size changes.
@immutable
class ReadingMark {
  const ReadingMark({required this.block, required this.char, required this.at});

  final int block;
  final int char;
  final DateTime at;

  (int, int) get anchor => (block, char);

  /// True when the text range [start, start+length) of [blockIndex] holds the mark.
  bool isIn(int blockIndex, int start, int length) =>
      blockIndex == block && char >= start && (char < start + length || length == 0);

  String encode() => '$block,$char,${at.millisecondsSinceEpoch}';

  static ReadingMark? decode(String? v) {
    final p = v?.split(',');
    if (p == null || p.length != 3) return null;
    final b = int.tryParse(p[0]), c = int.tryParse(p[1]), t = int.tryParse(p[2]);
    if (b == null || c == null || t == null) return null;
    return ReadingMark(block: b, char: c, at: DateTime.fromMillisecondsSinceEpoch(t));
  }
}

/// Persistent store of reading marks, keyed by the item's unique key
/// (e.g. "fr/b/jean-316", "fr/k/cours/01").
class BookmarkStore extends ChangeNotifier {
  BookmarkStore(this._prefs);
  final SharedPreferences _prefs;

  static String _k(String key) => 'mark:$key';

  ReadingMark? get(String key) => ReadingMark.decode(_prefs.getString(_k(key)));

  bool has(String key) => _prefs.containsKey(_k(key));

  void set(String key, int block, int char) {
    _prefs.setString(_k(key), ReadingMark(block: block, char: char, at: DateTime.now()).encode());
    notifyListeners();
  }

  void remove(String key) {
    _prefs.remove(_k(key));
    notifyListeners();
  }

  /// Restores a previous mark (used by "Undo").
  void restore(String key, ReadingMark? mark) {
    mark == null ? _prefs.remove(_k(key)) : _prefs.setString(_k(key), mark.encode());
    notifyListeners();
  }
}
