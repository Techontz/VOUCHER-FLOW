import 'package:flutter/foundation.dart';

/// Where the API lives.
///
/// The Android emulator reaches the host machine through 10.0.2.2, so the
/// default is chosen per platform. Override for a real device or a deployed
/// backend with --dart-define=API_URL=https://api.example.com/api
class VfConfig {
  const VfConfig._();

  static const _override = String.fromEnvironment('API_URL');

  static String get apiUrl {
    if (_override.isNotEmpty) return _override;

    // dart:io's Platform is unavailable on the web, so branch on the target.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  static const supportedLocales = ['en', 'sw'];
}
