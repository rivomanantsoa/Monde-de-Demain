/// Data shapes produced by content_pipeline/build_content.py.
/// Keys are kept short on the wire to save bytes.
class Language {
  Language({required this.code, required this.name, required this.native, required this.rtl});
  final String code;
  final String name;
  final String native;
  final bool rtl;

  factory Language.fromJson(Map<String, dynamic> j) => Language(
        code: j['code'] as String,
        name: j['name'] as String? ?? j['code'] as String,
        native: j['native'] as String? ?? j['code'] as String,
        rtl: j['rtl'] as bool? ?? false,
      );
}

/// Anything that can be downloaded and read: a brochure or a course lesson.
class Readable {
  Readable({
    required this.key,
    required this.path,
    required this.title,
    required this.size,
    required this.version,
    this.author = '',
    this.summary = '',
    this.hasCover = false,
    this.coverPath,
    this.date = '',
    this.year,
    this.articles = const [],
  });

  /// Unique local key, e.g. "fr/b/jean-316" or "fr/k/cours/01".
  final String key;

  /// Path of the gzipped pack relative to the content base URL.
  final String path;
  final String title;
  final int size;
  final String version;
  final String author;
  final String summary;
  final bool hasCover;
  final String? coverPath;

  /// Publication date as displayed by the site (commentaries).
  final String date;

  /// Magazine issues: year and article titles (the issue's table of contents).
  final int? year;
  final List<String> articles;
}

/// Commentaries list (`<lang>/commentaires.json`), newest first.
List<Readable> parseCommentaires(Map<String, dynamic> j) {
  final lang = j['lang'] as String;
  return [
    for (final c in (j['items'] as List? ?? const []))
      Readable(
        key: '$lang/m/${c['id']}',
        path: '$lang/m/${c['id']}.json.gz',
        title: c['t'] as String,
        author: c['a'] as String? ?? '',
        summary: c['s'] as String? ?? '',
        date: c['d'] as String? ?? '',
        size: (c['sz'] as num?)?.toInt() ?? 0,
        version: c['v'] as String? ?? '',
      ),
  ];
}

/// Magazine issues list (`<lang>/revues.json`), newest first.
List<Readable> parseRevues(Map<String, dynamic> j) {
  final lang = j['lang'] as String;
  return [
    for (final r in (j['items'] as List? ?? const []))
      Readable(
        key: '$lang/r/${r['id']}',
        path: '$lang/r/${r['id']}.json.gz',
        title: '${r['t']} ${r['y']}',
        year: (r['y'] as num?)?.toInt(),
        articles: [for (final a in (r['arts'] as List? ?? const [])) a as String],
        size: (r['sz'] as num?)?.toInt() ?? 0,
        version: r['v'] as String? ?? '',
        hasCover: r['c'] == true,
        coverPath: '$lang/c/r-${r['id']}.jpg',
      ),
  ];
}

class Course {
  Course({required this.id, required this.title, required this.summary, required this.lessons});
  final String id;
  final String title;
  final String summary;
  final List<Readable> lessons;

  int get totalSize => lessons.fold(0, (a, l) => a + l.size);
}

class Catalog {
  Catalog({required this.lang, required this.brochures, required this.courses});
  final String lang;
  final List<Readable> brochures;
  final List<Course> courses;

  bool get isEmpty => brochures.isEmpty && courses.isEmpty;

  factory Catalog.fromJson(Map<String, dynamic> j) {
    final lang = j['lang'] as String;
    final brochures = [
      for (final b in (j['brochures'] as List? ?? const []))
        Readable(
          key: '$lang/b/${b['id']}',
          path: '$lang/b/${b['id']}.json.gz',
          title: b['t'] as String,
          author: b['a'] as String? ?? '',
          summary: b['s'] as String? ?? '',
          size: (b['sz'] as num?)?.toInt() ?? 0,
          version: b['v'] as String? ?? '',
          hasCover: b['c'] == true,
          coverPath: '$lang/c/${b['id']}.jpg',
        ),
    ];
    final courses = [
      for (final c in (j['courses'] as List? ?? const []))
        Course(
          id: c['id'] as String,
          title: c['t'] as String,
          summary: c['s'] as String? ?? '',
          lessons: [
            for (final l in (c['lessons'] as List? ?? const []))
              Readable(
                key: '$lang/k/${c['id']}/${l['id']}',
                path: '$lang/k/${c['id']}/${l['id']}.json.gz',
                title: l['t'] as String,
                size: (l['sz'] as num?)?.toInt() ?? 0,
                version: l['v'] as String? ?? '',
              ),
          ],
        ),
    ];
    return Catalog(lang: lang, brochures: brochures, courses: courses);
  }
}

/// One block of reading content: [type, text].
/// Types: h1 (article title in a magazine issue), by (article author),
/// h2, h3, p, q (quote), li, ol, img (text = url).
class Block {
  const Block(this.type, this.text);
  final String type;
  final String text;
}

class Pack {
  Pack({required this.title, required this.author, required this.blocks});
  final String title;
  final String author;
  final List<Block> blocks;

  /// For each block, its number within a run of consecutive "ol" items (1, 2…).
  late final List<int> listNumbers = () {
    final out = List<int>.filled(blocks.length, 0);
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].type == 'ol') out[i] = (i > 0 ? out[i - 1] : 0) + 1;
    }
    return out;
  }();

  /// Magazine issues: (block index, title) of each article, for the contents.
  late final List<(int, String)> articles = [
    for (var i = 0; i < blocks.length; i++)
      if (blocks[i].type == 'h1') (i, blocks[i].text),
  ];

  factory Pack.fromJson(Map<String, dynamic> j) => Pack(
        title: j['t'] as String? ?? '',
        author: j['a'] as String? ?? '',
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            Block(b[0] as String, b[1] as String),
        ],
      );
}
