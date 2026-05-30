import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:ma5zony/app.dart';
import 'package:ma5zony/firebase_options.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

/// Sentry DSN is injected at build time:
///   flutter build web --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture all Flutter errors into window.__flutterErrors for Playwright inspection
  FlutterError.onError = (FlutterErrorDetails details) {
    // ignore: avoid_print
    print('[FLUTTER-ERROR] ${details.exceptionAsString()}');
    FlutterError.dumpErrorToConsole(details);
  };

  // Replace Flutter's default red error box with a branded, friendly fallback
  // so a single failing widget never paints a scary red screen over the app.
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      _FriendlyErrorWidget(details: details);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final appState = AppState()..loadAll();

  final app = MultiProvider(
    providers: [ChangeNotifierProvider.value(value: appState)],
    child: Ma5zonyApp(appState: appState),
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

/// Branded fallback shown in place of any widget that throws during build.
/// Keeps the app usable (the rest of the shell still works) instead of
/// painting Flutter's default red error box across the page.
class _FriendlyErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _FriendlyErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: AppColors.background,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.errorBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong on this screen',
                textAlign: TextAlign.center,
                style: AppTextStyles.h3,
              ),
              const SizedBox(height: 8),
              Text(
                'The rest of the app is still working. Try going back, '
                'reloading the page, or navigating to another section.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

