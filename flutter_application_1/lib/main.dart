import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_config.dart';
import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/language_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.create();
  runApp(AppScope(state: state, child: const MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final code = app.lang;
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: app.themeMode,
      // The UI follows the chosen content language (RTL for Arabic, etc.).
      locale: code == null ? null : Locale(code),
      supportedLocales: const [
        Locale('fr'), Locale('en'), Locale('es'), Locale('de'), Locale('nl'),
        Locale('pt'), Locale('ru'), Locale('ar'), Locale('sw'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: code == null ? const LanguageScreen(firstRun: true) : const HomeScreen(),
    );
  }
}
