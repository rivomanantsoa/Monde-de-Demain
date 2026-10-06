import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../theme.dart';

/// First launch (and Settings > Language): pick the language that both the
/// interface and the brochures/courses will use.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh the list quietly; the bundled/cached list is shown meanwhile.
    AppScope.read(context).refreshLanguages();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final current = app.lang;
    // Say "choose your language" in every available language.
    final prompts = {for (final l in app.languages) S(l.code).chooseLanguage}.toList();

    return Scaffold(
      backgroundColor: Brand.black,
      appBar: widget.firstRun
          ? null
          : AppBar(title: Text(app.s.language)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            if (widget.firstRun)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 48, height: 6, color: Brand.red),
                      const SizedBox(height: 20),
                      const Text(
                        kAppName,
                        style: TextStyle(
                          fontFamily: Brand.serif,
                          fontSize: 36,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Brand.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        prompts.join('  ·  '),
                        style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList.separated(
                itemCount: app.languages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final l = app.languages[i];
                  final selected = l.code == current;
                  return Material(
                    key: ValueKey(l.code),
                    color: selected ? Brand.red : const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        await app.setLanguage(l.code);
                        if (!widget.firstRun && nav.canPop()) nav.pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.native,
                                    textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr,
                                    style: const TextStyle(
                                      color: Brand.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (l.native != l.name)
                                    Text(
                                      l.name,
                                      style: TextStyle(
                                        color: selected ? Colors.white70 : const Color(0xFF9E9E9E),
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              selected ? Icons.check_circle : Icons.chevron_right,
                              color: selected ? Brand.white : const Color(0xFF757575),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
