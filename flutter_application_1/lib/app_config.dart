/// Where the content packs live (the `out/` folder produced by
/// content_pipeline/build_content.py, uploaded to any static host).
///
/// Override at build time:
///   flutter build apk --dart-define=CONTENT_BASE_URL=https://example.org/mdd/
///
/// The default points at the host machine from an Android emulator, so
/// `python3 -m http.server 8000` inside content_pipeline/out works for testing.
const String kContentBaseUrl = String.fromEnvironment(
  'CONTENT_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/',
);

const String kAppName = 'Le Monde de Demain';
