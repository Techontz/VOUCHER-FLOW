import 'package:flutter/foundation.dart';

/// Development-only hooks for screenshot testing: on a profile web build,
/// the page's query string
/// `?token=<sanctum token>&route=/reports&theme=light&voucher=18&push=/platform/company&id=1`;
/// on a debug build for a simulator, the same string passed as
/// `--dart-define=VF_DEV=token=…&route=/erp/stock&theme=dark`.
///
/// Compiled to nothing in release builds (kReleaseMode is a constant), so no
/// store build or device ever honours them.
class DevHooks {
  const DevHooks._();

  static const _define = String.fromEnvironment('VF_DEV');

  static Map<String, String> get _q {
    if (kReleaseMode) return const {};
    if (kIsWeb) return Uri.base.queryParameters;
    return _define.isEmpty ? const {} : Uri.splitQueryString(_define);
  }

  static String? get token => _q['token'];
  static String? get route => _q['route'];
  static String? get theme => _q['theme'];
  static String? get locale => _q['locale'];

  /// A count to start with on the Count tab, for a screenshot of one in
  /// progress: `count=<warehouse id>:<product id>=<qty>,<product id>=<qty>`.
  static String? get count => _q['count'];

  /// A page to push over the shell after it opens, with its arguments.
  static String? get push => _q['push'];
  static Map<String, String> get pushArgs => Map.of(_q)
    ..removeWhere((k, _) => const {'token', 'route', 'theme', 'locale', 'push', 'count'}.contains(k));
}
