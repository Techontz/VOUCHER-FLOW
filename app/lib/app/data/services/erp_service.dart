import 'dart:async';

import 'package:get/get.dart';

import '../models/erp_models.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'session_service.dart';

/// The company's ERP configuration and the signed-in person's permissions,
/// read once per session from GET /erp/config and shared by every screen
/// (the web's `useErp`).
///
/// Screens ask [can] and [has]; they never work out a role's rights
/// themselves, and the API refuses the same things again on every call.
class ErpService extends GetxService {
  ErpService(this._api, this._session);

  final ApiService _api;
  final SessionService _session;

  /// The shared instance, registered on first use.
  static ErpService get to => Get.isRegistered<ErpService>()
      ? Get.find<ErpService>()
      : Get.put(
          ErpService(Get.find<ApiService>(), Get.find<SessionService>()),
          permanent: true,
        );

  /// Null until read, and when the company has no ERP or the read failed:
  /// the person then has VouchFlow alone.
  final config = Rxn<ErpConfig>();

  /// True once the read for the current person has finished, whatever its
  /// outcome, so the shell knows when it may decide between the launcher
  /// and a single app.
  final settled = false.obs;

  /// The person the cached configuration belongs to: a different sign-in
  /// must never see the previous person's permissions.
  int? _for;
  Future<ErpConfig?>? _inflight;
  Worker? _userWorker;

  @override
  void onInit() {
    super.onInit();
    // Sign-in, sign-out and switching account all pass through the user.
    _userWorker = ever<AppUser?>(_session.user, (u) {
      if (u == null) {
        forget();
      } else if (u.id != _for) {
        unawaited(refresh());
      }
    });
    if (_session.user.value != null) unawaited(refresh());
  }

  @override
  void onClose() {
    _userWorker?.dispose();
    super.onClose();
  }

  bool can(String permission) => config.value?.can(permission) ?? false;

  bool has(String module) => config.value?.has(module) ?? false;

  String get currency => config.value?.baseCurrency ?? 'TZS';

  /// The configuration for the signed-in person, read at most once.
  Future<ErpConfig?> ensure() {
    final me = _session.user.value;
    if (settled.value && me != null && me.id == _for) {
      return Future.value(config.value);
    }
    return refresh();
  }

  /// Re-reads the configuration (after sign-in, or when a screen is told
  /// its permissions changed).
  Future<ErpConfig?> refresh() {
    return _inflight ??= () async {
      final me = _session.user.value;
      try {
        // The platform operator has no company and therefore no ERP.
        if (me == null || me.isSuperAdmin) {
          config.value = null;
        } else {
          final payload = await _api.get('/erp/config');
          final data = payload is Map ? payload['data'] : null;
          config.value = data is Map
              ? ErpConfig.fromJson(Map<String, dynamic>.from(data))
              : null;
        }
      } catch (_) {
        // No ERP (an older plan, a lapsed subscription, offline): the
        // person keeps VouchFlow, which needs no configuration.
        config.value = null;
      } finally {
        _for = me?.id;
        settled.value = true;
        _inflight = null;
      }
      return config.value;
    }();
  }

  /// Clears everything, on sign-out.
  void forget() {
    config.value = null;
    settled.value = false;
    _for = null;
  }
}
