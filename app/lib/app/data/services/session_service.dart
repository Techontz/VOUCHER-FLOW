import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/models.dart';
import 'api_service.dart';

/// Holds the signed-in user, their company and the app-wide preferences.
/// Registered permanently, so every controller resolves the same instance.
class SessionService extends GetxService {
  SessionService(this._api);

  final ApiService _api;

  final user = Rxn<AppUser>();
  final company = Rxn<Company>();
  final unread = 0.obs;
  final locale = 'en'.obs;
  final themeMode = ThemeMode.dark.obs;
  final booting = true.obs;

  bool get isSignedIn => user.value != null;
  AppUser get me => user.value!;

  Future<SessionService> init() async {
    locale.value = _api.locale;
    // The device's stored appearance applies before anything is fetched, so the
    // first frame is already correct — dark unless this device chose light.
    themeMode.value = _modeFrom(_api.theme);
    Get.changeThemeMode(themeMode.value);
    _api.onUnauthorised.add(() => _clear());

    if (_api.hasToken) {
      try {
        await refresh();
      } catch (_) {
        await _api.setToken(null);
      }
    }
    booting.value = false;
    return this;
  }

  Future<void> signIn(String email, String password) async {
    final data =
        await _api.post('/auth/login', {
              'email': email,
              'password': password,
              'device_name': 'VouchFlow mobile',
            })
            as Map<String, dynamic>;

    await _api.setToken('${data['token']}');
    _apply(data);
    await refreshUnread();
  }

  Future<void> refresh() async {
    final data = await _api.get('/auth/me') as Map<String, dynamic>;
    _apply(data);
    await refreshUnread();
  }

  void _apply(Map<String, dynamic> data) {
    user.value = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    company.value = data['company'] is Map<String, dynamic>
        ? Company.fromJson(data['company'] as Map<String, dynamic>)
        : null;

    final preferred = user.value!.locale;
    if (preferred != locale.value) {
      setLocale(preferred, persist: false);
    }
    themeMode.value = user.value!.theme == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    Get.changeThemeMode(themeMode.value);
  }

  Future<void> refreshUnread() async {
    try {
      final data =
          await _api.get('/notifications/unread-count') as Map<String, dynamic>;
      unread.value = (data['unread_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // A failed badge poll should never interrupt the user.
    }
  }

  Future<void> setLocale(String code, {bool persist = true}) async {
    locale.value = code;
    await _api.setLocale(code);
    Get.updateLocale(Locale(code));
    if (persist && isSignedIn) {
      try {
        await _api.put('/profile', {'locale': code});
      } catch (_) {}
    }
  }

  Future<void> toggleTheme() async {
    final next = themeMode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;

    _applyTheme(next);

    if (isSignedIn) {
      try {
        await _api.put('/profile', {'theme': _nameFor(next)});
      } catch (_) {
        // The device keeps the choice even if the account could not be updated.
      }
    }
  }

  static ThemeMode _modeFrom(String? value) =>
      value == 'light' ? ThemeMode.light : ThemeMode.dark;

  static String _nameFor(ThemeMode mode) =>
      mode == ThemeMode.light ? 'light' : 'dark';

  /// Applies the appearance and remembers it on this device.
  void _applyTheme(ThemeMode mode) {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    unawaited(_api.setTheme(_nameFor(mode)));
  }

  Future<void> signOut() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // The local session is cleared regardless.
    }
    await _clear();
  }

  Future<void> _clear() async {
    await _api.setToken(null);
    user.value = null;
    company.value = null;
    unread.value = 0;
  }
}
