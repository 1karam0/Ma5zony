import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:ma5zony/app.dart';
import 'package:ma5zony/firebase_options.dart';
import 'package:ma5zony/providers/app_state.dart';

/// Sentry DSN is injected at build time:
///   flutter build web --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final app = MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AppState()..loadAll())],
    child: const Ma5zonyApp(),
  );

  if (_sentryDsn.isEmpty) {
    // No DSN configured — run without Sentry (dev / CI)
    runApp(app);
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.tracesSampleRate = 0.2;
        options.environment =
            const String.fromEnvironment('FLUTTER_ENV', defaultValue: 'production');
      },
      appRunner: () => runApp(app),
    );
  }
}
