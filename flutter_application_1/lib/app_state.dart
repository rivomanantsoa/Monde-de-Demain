import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'bookmarks/bookmarks.dart';
import 'l10n.dart';
import 'models.dart';

/// Single source of truth for the app: settings, catalog, downloads.
///
/// Data-saving rules:
///  * index/catalog are fetched with conditional requests (ETag /
///    Last-Modified): when nothing changed the server answers 304, ~0 bytes.
///  * packs are only fetched when the user taps "Download", never in the
///    background, and updates are offered, not forced.
///  * covers are off by default.
/// Storage-saving rules:
///  * packs stay gzipped on disk (~25-40 KB each) and are unzipped in memory
///    only while reading.
///  * nothing is stored that the user did not ask for (except tiny catalogs).
class AppState extends ChangeNotifier {
  AppState(this._prefs, this._root);

  final SharedPreferences _prefs;
  final Directory _root;
  final http.Client _http = http.Client();

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/mdd');
    await root.create(recursive: true);
    final s = AppState(prefs, root);
    await s._loadManifest();
    await s._loadLanguagesFromCache();
    return s;
  }

  /// Reading marks for every reader (brochures, lessons, …).
  late final BookmarkStore bookmarks = BookmarkStore(_prefs)..addListener(notifyListeners);

  // ---------------------------------------------------------------- settings
  String? get lang => _prefs.getString('lang');
  S get s => S(lang ?? 'en');
  Language? get language => languages.where((l) => l.code == lang).firstOrNull;
  bool get rtl => language?.rtl ?? false;

  bool get showCovers => _prefs.getBool('showCovers') ?? false;
  set showCovers(bool v) {
    _prefs.setBool('showCovers', v);
    notifyListeners();
  }

  double get textScale => _prefs.getDouble('textScale') ?? 1.0;
  set textScale(double v) {
    _prefs.setDouble('textScale', v);
    notifyListeners();
  }

  ThemeMode get themeMode => ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
  set themeMode(ThemeMode m) {
    _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  /// Book-like pages (default) or continuous scrolling.
  bool get pagedReading => _prefs.getBool('paged') ?? true;
  set pagedReading(bool v) {
    _prefs.setBool('paged', v);
    notifyListeners();
  }

  /// Page mode position: (block index, char offset), independent of text size.
  (int, int) readingAnchor(String key) {
    final v = _prefs.getStringList('anchor:$key');
    if (v == null || v.length != 2) return (-1, 0);
    return (int.tryParse(v[0]) ?? -1, int.tryParse(v[1]) ?? 0);
  }

  void saveReadingAnchor(String key, (int, int) a) =>
      _prefs.setStringList('anchor:$key', ['${a.$1}', '${a.$2}']);

  /// Last opened tab of the "Read" screen (defaults to Brochures).
  int get readTab => _prefs.getInt('readTab') ?? 1;
  set readTab(int i) => _prefs.setInt('readTab', i);

  double readingOffset(String key) => _prefs.getDouble('pos:$key') ?? 0;
  void saveReadingOffset(String key, double offset) => _prefs.setDouble('pos:$key', offset);

  Future<void> setLanguage(String code) async {
    await _prefs.setString('lang', code);
    catalog = null;
    sections.clear();
    sectionFromCache.clear();
    notifyListeners();
    await refreshCatalog();
  }

  // ---------------------------------------------------------------- network
  Uri _url(String path) => Uri.parse(kContentBaseUrl).resolve(path);
  File _file(String path) => File('${_root.path}/$path');

  /// Fetches a small JSON file, using the local copy when the server says it
  /// has not changed (304) or when offline. Returns null if neither works.
  Future<({Object? json, bool fromCache})> _getJson(String path) async {
    final local = _file(path);
    final headers = <String, String>{};
    if (await local.exists()) {
      final etag = _prefs.getString('etag:$path');
      final lm = _prefs.getString('lm:$path');
      if (etag != null) headers['If-None-Match'] = etag;
      if (lm != null) headers['If-Modified-Since'] = lm;
    }
    try {
      final r = await _http.get(_url(path), headers: headers).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        await local.parent.create(recursive: true);
        await local.writeAsBytes(r.bodyBytes);
        final etag = r.headers['etag'];
        final lm = r.headers['last-modified'];
        etag != null ? _prefs.setString('etag:$path', etag) : _prefs.remove('etag:$path');
        lm != null ? _prefs.setString('lm:$path', lm) : _prefs.remove('lm:$path');
        return (json: jsonDecode(utf8.decode(r.bodyBytes)), fromCache: false);
      }
      if (r.statusCode == 304 && await local.exists()) {
        return (json: jsonDecode(await local.readAsString()), fromCache: false);
      }
    } catch (e) {
      debugPrint('GET $path failed: $e');
    }
    if (await local.exists()) {
      return (json: jsonDecode(await local.readAsString()), fromCache: true);
    }
    return (json: null, fromCache: true);
  }

  // ---------------------------------------------------------------- languages
  List<Language> languages = [];

  Future<void> _loadLanguagesFromCache() async {
    final local = _file('index.json');
    final String raw = await local.exists()
        ? await local.readAsString()
        : await rootBundle.loadString('assets/index.json');
    languages = _parseLanguages(jsonDecode(raw));
  }

  List<Language> _parseLanguages(Object? json) => [
        for (final l in ((json as Map?)?['languages'] as List? ?? const []))
          Language.fromJson(l as Map<String, dynamic>),
      ];

  Future<void> refreshLanguages() async {
    final r = await _getJson('index.json');
    final parsed = _parseLanguages(r.json);
    if (parsed.isNotEmpty) {
      languages = parsed;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- catalog
  Catalog? catalog;
  bool catalogLoading = false;
  bool catalogFromCache = false;

  Future<void> refreshCatalog() async {
    final code = lang;
    if (code == null || catalogLoading) return;
    catalogLoading = true;
    notifyListeners();
    final r = await _getJson('$code/catalog.json');
    if (code == lang) {
      if (r.json != null) catalog = Catalog.fromJson(r.json as Map<String, dynamic>);
      catalogFromCache = r.fromCache;
    }
    catalogLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- sections
  /// Large lists (commentaires, revues) are separate files, fetched only
  /// when their tab is opened — and then with conditional requests.
  static const sectionNames = ['commentaires', 'revues'];
  final Map<String, List<Readable>> sections = {};
  final Set<String> sectionLoading = {};
  final Set<String> sectionFromCache = {};

  Future<void> loadSection(String name) async {
    final code = lang;
    if (code == null || sectionLoading.contains(name)) return;
    sectionLoading.add(name);
    notifyListeners();
    final r = await _getJson('$code/$name.json');
    if (code == lang) {
      final j = r.json as Map<String, dynamic>?;
      if (j != null) {
        sections[name] = name == 'revues' ? parseRevues(j) : parseCommentaires(j);
      }
      r.fromCache ? sectionFromCache.add(name) : sectionFromCache.remove(name);
    }
    sectionLoading.remove(name);
    notifyListeners();
  }

  /// Every known item of the current language, by key.
  Map<String, Readable> get knownItems => {
        for (final b in catalog?.brochures ?? const <Readable>[]) b.key: b,
        for (final c in catalog?.courses ?? const <Course>[])
          for (final l in c.lessons) l.key: l,
        for (final list in sections.values)
          for (final r in list) r.key: r,
      };

  // ---------------------------------------------------------------- downloads
  /// key -> {"v": version, "sz": bytes on disk, "t": title}
  Map<String, Map<String, dynamic>> downloads = {};
  final Map<String, double?> inProgress = {};

  File get _manifest => _file('downloads.json');

  Future<void> _loadManifest() async {
    try {
      if (await _manifest.exists()) {
        final m = jsonDecode(await _manifest.readAsString()) as Map<String, dynamic>;
        downloads = m.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {
      downloads = {};
    }
  }

  Future<void> _saveManifest() => _manifest.writeAsString(jsonEncode(downloads));

  bool isDownloaded(Readable r) => downloads.containsKey(r.key);
  bool hasUpdate(Readable r) =>
      isDownloaded(r) && r.version.isNotEmpty && downloads[r.key]!['v'] != r.version;

  /// Downloads one pack. Returns false on network error.
  Future<bool> download(Readable r) async {
    if (inProgress.containsKey(r.key)) return true;
    inProgress[r.key] = null;
    notifyListeners();
    try {
      final req = http.Request('GET', _url(r.path));
      final resp = await _http.send(req).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
      final total = resp.contentLength ?? r.size;
      final bytes = <int>[];
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (total > 0) {
          inProgress[r.key] = (bytes.length / total).clamp(0, 1).toDouble();
          notifyListeners();
        }
      }
      // Some servers transparently un-gzip; keep it compressed on disk anyway.
      final isGz = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
      final data = isGz ? bytes : gzip.encode(bytes);
      // Validate before saving so a broken file never replaces a good one.
      jsonDecode(utf8.decode(gzip.decode(data)));
      final f = _file(r.path);
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(f.path);
      downloads[r.key] = {'v': r.version, 'sz': data.length, 't': r.title, 'p': r.path};
      await _saveManifest();
      return true;
    } catch (e) {
      debugPrint('download ${r.path} failed: $e');
      return false;
    } finally {
      inProgress.remove(r.key);
      notifyListeners();
    }
  }

  Future<void> delete(String key) async {
    final entry = downloads.remove(key);
    final path = entry?['p'] as String?;
    if (path != null) {
      final f = _file(path);
      if (await f.exists()) await f.delete();
    }
    _prefs.remove('pos:$key');
    _prefs.remove('anchor:$key');
    bookmarks.remove(key);
    await _saveManifest();
    notifyListeners();
  }

  /// Removes every downloaded pack and cached cover (catalogs are kept).
  Future<void> deleteAll() async {
    for (final key in downloads.keys.toList()) {
      _prefs.remove('pos:$key');
      _prefs.remove('anchor:$key');
      bookmarks.remove(key);
    }
    downloads.clear();
    _coverFutures.clear();
    await _saveManifest();
    for (final e in _root.listSync()) {
      if (e is Directory) {
        for (final sub in ['b', 'k', 'c']) {
          final d = Directory('${e.path}/$sub');
          if (d.existsSync()) await d.delete(recursive: true);
        }
      }
    }
    notifyListeners();
  }

  Future<Pack> readPack(Readable r) async {
    final bytes = await _file(r.path).readAsBytes();
    return compute(_decodePack, bytes);
  }

  /// Bytes used on disk by this app's content (packs + covers + catalogs).
  Future<int> storageBytes() async {
    var total = 0;
    await for (final e in _root.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  // ---------------------------------------------------------------- covers
  final Map<String, Future<File?>> _coverFutures = {};

  /// Cached cover thumbnail (~8 KB). Fetched only when covers are enabled;
  /// with covers off, only an already-stored thumbnail is shown.
  Future<File?> cover(Readable r) {
    final path = r.coverPath;
    if (!r.hasCover || path == null) return Future.value(null);
    final f = _file(path);
    final pending = _coverFutures[path];
    if (pending != null) return pending;
    if (!showCovers) return f.exists().then((ok) => ok ? f : null);
    return _coverFutures[path] = () async {
      if (await f.exists()) return f;
      try {
        final resp = await _http.get(_url(path)).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          await f.parent.create(recursive: true);
          await f.writeAsBytes(resp.bodyBytes);
          return f;
        }
      } catch (_) {}
      _coverFutures.remove(path); // allow a retry later
      return null;
    }();
  }
}

Pack _decodePack(List<int> gz) =>
    Pack.fromJson(jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>);

/// Makes [AppState] reachable from any widget: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
