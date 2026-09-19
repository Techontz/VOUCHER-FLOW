import 'package:flutter/foundation.dart';

/// Where the API lives.
///
/// A release build talks to production unless told otherwise. Debug and
/// profile builds talk to `php artisan serve` on the development machine —
/// the Android emulator reaches it through 10.0.2.2. Override either with
/// --dart-define=API_URL=https://api.example.com/api
class VfConfig {
  const VfConfig._();

  static const _override = String.fromEnvironment('API_URL');

  /// The Laravel API is connected, so the app talks to it by default. The
  /// in-app fixture in `data/mock/` is still there for working offline or on
  /// a machine with no backend: build with --dart-define=API_MODE=mock.
  /// Every screen, controller and model is identical either way.
  static const apiMode = String.fromEnvironment(
    'API_MODE',
    defaultValue: 'live',
  );
  static bool get useMock => apiMode != 'live';

  /// The live API. Store builds use this with no extra flags.
  static const productionApiUrl = 'https://api.voucherflow.co.tz/api';

  static String get apiUrl {
    if (_override.isNotEmpty) return _override;
    if (kReleaseMode) return productionApiUrl;

    // dart:io's Platform is unavailable on the web, so branch on the target.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  static const supportedLocales = ['en', 'sw'];
}
