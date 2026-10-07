import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models.dart';
import 'package:flutter_application_1/reader/paginator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pagination keeps every character, in order, within page height', (tester) async {
    final f = File('../content_pipeline/out/fr/b/comprendre-la-prophetie-biblique.json.gz');
    final pack = Pack.fromJson(jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))));
    late ReaderStyles st;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      st = ReaderStyles(c, 1.0);
      return const SizedBox();
    })));
    for (final size in [const Size(316, 600), const Size(400, 800)]) {
      final pages = paginate(pack, st, size, TextDirection.ltr);
      // Rebuild each block's plain text from its fragments.
      final byBlock = <int, StringBuffer>{};
      for (final p in pages) {
        var used = 0.0;
        for (final it in p.items) {
          byBlock.putIfAbsent(it.blockIndex, StringBuffer.new).write(it.runs.map((r) => r.text).join());
          if (it.type == 'img') {
            used += it.gapTop + ReaderStyles.imageHeight;
          } else {
            final tp = TextPainter(
              text: spanOf(it.runs, st.styleFor(it.type)),
              textDirection: TextDirection.ltr,
              textScaler: st.textScaler,
            )..layout(maxWidth: size.width - st.insetFor(it.type));
            used += it.gapTop + tp.height;
          }
          expect(used, lessThanOrEqualTo(size.height), reason: 'page overflow');
          used += it.gapBottom;
        }
      }
      for (var i = 0; i < pack.blocks.length; i++) {
        if (pack.blocks[i].type == 'img') continue;
        final plain = parseRuns(pack.blocks[i].text).map((r) => r.text).join();
        expect(byBlock[i].toString().replaceAll(RegExp(r'\s'), ''), plain.replaceAll(RegExp(r'\s'), ''),
            reason: 'block $i');
      }
      // ignore: avoid_print
      print('${size.width}x${size.height}: ${pages.length} pages');
      expect(pageForAnchor(pages, pages[5].anchor), 5);
    }
  });
}
