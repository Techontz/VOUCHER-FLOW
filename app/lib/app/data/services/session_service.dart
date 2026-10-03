import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/dev_hooks.dart';

import '../../core/theme.dart';
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

  /// The company's interface palette. The app's themes are rebuilt from it.
  final accent = VfAccentPalette.blue.obs;
  final booting = true.obs;

  bool get isSignedIn => user.value != null;

  /// The signed-in person. After signing out (or a 401) the screens still on
  /// their way out may rebuild once more; they keep seeing the departing user
  /// rather than failing on an empty session.
  AppUser get me {
    final u = user.value;
    if (u != null) return _lastMe = u;
    return _lastMe!;
  }

  AppUser? _lastMe;

  Future<SessionService> init() async {
    locale.value = _api.locale;
    // The device's stored appearance applies before anything is fetched, so the
    // first frame is already correct — dark unless this device chose light.
    themeMode.value = _modeFrom(_api.theme);
    Get.changeThemeMode(themeMode.value);
    applyAccent(_api.accent, persist: false);
    _api.onUnauthorised.add(() => _clear());
    // A refusal because the company awaits approval: re-read the account so
    // the shell swaps to the waiting screen.
    _api.onCompanyPending.add(() {
      if (company.value?.isPending == true) return;
      refresh().catchError((_) {});
    });

    // Development only (profile web builds): sign in with a given token.
    if (DevHooks.token != null) await _api.setToken(DevHooks.token);
    if (DevHooks.theme != null) {
      themeMode.value = _modeFrom(DevHooks.theme);
      Get.changeThemeMode(themeMode.value);
    }

    if (_api.hasToken) {
      try {
        await refresh();
      } catch (_) {
        await _api.setToken(null);
      }
    }
    // Development only: a requested appearance wins over the stored one.
    if (DevHooks.theme != null) _applyTheme(_modeFrom(DevHooks.theme));
    if (DevHooks.locale != null) await setLocale(DevHooks.locale!, persist: false);
    booting.value = false;
    return this;
  }

  static const _deviceName = 'VouchFlow mobile';

  /// Checks the password. Returns null when the account is signed in straight
  /// away, or the [LoginChallenge] to complete when a code is required.
  Future<LoginChallenge?> signIn(String email, String password) async {
    final data =
        await _api.post('/auth/login', {
              'email': email,
              'password': password,
              'device_name': _deviceName,
            })
            as Map<String, dynamic>;

    if (data['requires_verification'] == true) {
      return LoginChallenge.fromJson(data);
    }

    await _startSession(data);
    return null;
  }

  /// Sends a sign-in code by [channel] ('email' or 'sms').
  Future<CodeDispatch> sendLoginCode(String challenge, String channel) async {
    final data =
        await _api.post('/auth/login/send-code', {
              'challenge': challenge,
              'channel': channel,
            })
            as Map<String, dynamic>;
    return CodeDispatch.fromJson(data);
  }

  /// Completes the second step and signs in exactly as a password-only
  /// sign-in does.
  Future<void> verifyLogin(String challenge, String code) async {
    final data =
        await _api.post('/auth/login/verify', {
              'challenge': challenge,
              'code': code,
              'device_name': _deviceName,
            })
            as Map<String, dynamic>;
    await _startSession(data);
  }

  /// Starts a session from any response that carries `token`, `user` and
  /// `company` — registration answers with one, as the web's applySession.
  Future<void> startSessionFrom(Map<String, dynamic> data) => _startSession(data);

  Future<void> _startSession(Map<String, dynamic> data) async {
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
    themeMode.value = user.value!.theme == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
    Get.changeThemeMode(themeMode.value);

    final colour = company.value?.colorTheme;
    if (colour != null) applyAccent(colour);
  }

  /// Switches the interface palette. Also used by the branding screen to
  /// preview a colour before it is saved; persist only what the company has.
  void applyAccent(String? key, {bool persist = true}) {
    final palette = VfAccentPalette.of(key);
    VfColors.palette = palette;
    accent.value = palette;
    if (persist) unawaited(_api.setAccent(palette.key));
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

/// One way a sign-in code can reach the user, with the address masked.
class VerificationChannel {
  const VerificationChannel(this.channel, this.destination);

  factory VerificationChannel.fromJson(Map<String, dynamic> json) =>
      VerificationChannel('${json['channel']}', '${json['destination'] ?? ''}');

  final String channel;
  final String destination;
}

/// The pending second step of a sign-in: the password was right, a code is
/// still needed. [challenge] is opaque and only ever sent back.
class LoginChallenge {
  const LoginChallenge({
    required this.challenge,
    required this.channels,
    this.sentTo,
    this.expiresIn,
    this.codeExpiresIn,
    this.resendIn,
  });

  factory LoginChallenge.fromJson(Map<String, dynamic> json) => LoginChallenge(
    challenge: '${json['challenge']}',
    channels: ((json['channels'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VerificationChannel.fromJson)
        .toList(),
    sentTo: json['sent_to'] as String?,
    expiresIn: (json['expires_in'] as num?)?.toInt(),
    codeExpiresIn: (json['code_expires_in'] as num?)?.toInt(),
    resendIn: (json['resend_in'] as num?)?.toInt(),
  );

  final String challenge;
  final List<VerificationChannel> channels;

  /// Set when the code has already been sent — the only channel on offer.
  final String? sentTo;
  final int? expiresIn, codeExpiresIn, resendIn;

  VerificationChannel? channelFor(String? name) =>
      channels.where((c) => c.channel == name).firstOrNull;
}

/// The API's answer to a code being sent.
class CodeDispatch {
  const CodeDispatch({
    required this.sentTo,
    required this.destination,
    this.codeExpiresIn,
    this.resendIn,
    this.sendsRemaining,
  });

  factory CodeDispatch.fromJson(Map<String, dynamic> json) => CodeDispatch(
    sentTo: '${json['sent_to']}',
    destination: '${json['destination'] ?? ''}',
    codeExpiresIn: (json['code_expires_in'] as num?)?.toInt(),
    resendIn: (json['resend_in'] as num?)?.toInt(),
    sendsRemaining: (json['sends_remaining'] as num?)?.toInt(),
  );

  final String sentTo, destination;
  final int? codeExpiresIn, resendIn, sendsRemaining;
}
