import 'package:flutter/foundation.dart';

/// Development-only hooks for screenshot testing a profile web build:
/// `?token=<sanctum token>&route=/reports&theme=light&voucher=18&push=/platform/company&id=1`.
///
/// Compiled to nothing in release builds (kReleaseMode is a constant), and
/// only read on the web, so no store build or device ever honours them.
class DevHooks {
  const DevHooks._();

  static Map<String, String> get _q =>
      (!kReleaseMode && kIsWeb) ? Uri.base.queryParameters : const {};

  static String? get token => _q['token'];
  static String? get route => _q['route'];
  static String? get theme => _q['theme'];
  static String? get locale => _q['locale'];

  /// A page to push over the shell after it opens, with its arguments.
  static String? get push => _q['push'];
  static Map<String, String> get pushArgs => Map.of(_q)..removeWhere((k, _) => const {'token', 'route', 'theme', 'locale', 'push'}.contains(k));
}
