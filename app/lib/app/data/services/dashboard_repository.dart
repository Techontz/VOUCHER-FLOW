import 'package:get/get.dart';

import '../models/dashboard_models.dart';
import '../models/models.dart';
import 'api_service.dart';

/// The dashboard, the company's approval routes (for list progress) and the
/// notification inbox.
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static DashboardRepository get to => Get.isRegistered<DashboardRepository>()
      ? Get.find<DashboardRepository>()
      : Get.put(DashboardRepository(Get.find<ApiService>()), permanent: true);

  Future<DashboardData> dashboard() async => DashboardData.fromJson(
    Map<String, dynamic>.from(await _api.get('/dashboard') as Map),
  );

  /* Routes are cached per company, never globally: signing into another
     tenant must not draw the first company's routes on the second's vouchers. */
  final _routes = <int, List<QueueWorkflow>>{};
  final _inflight = <int, Future<List<QueueWorkflow>>>{};

  Future<List<QueueWorkflow>> workflows(int companyId) {
    final cached = _routes[companyId];
    if (cached != null) return Future.value(cached);
    return _inflight[companyId] ??= () async {
      try {
        final payload = await _api.get('/workflows') as Map;
        final rows = (payload['data'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => QueueWorkflow.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return _routes[companyId] = rows;
      } finally {
        _inflight.remove(companyId);
      }
    }();
  }

  /// Drops cached routes — after a workflow is edited, or on sign-out.
  void invalidateWorkflows() => _routes.clear();

  Future<NotificationPage<AppNotificationItem>> notifications() async {
    final payload = Map<String, dynamic>.from(
      await _api.get('/notifications', {'per_page': 50}) as Map,
    );
    final items = (payload['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => AppNotificationItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final meta = payload['meta'];
    final unread = meta is Map && meta['unread_count'] is num
        ? (meta['unread_count'] as num).toInt()
        : items.where((i) => i.isUnread).length;
    return NotificationPage(items, unread);
  }

  Future<void> markNotificationRead(int id) =>
      _api.post('/notifications/$id/read');

  /// Marks the whole inbox read; returns how many changed.
  Future<int> markAllNotificationsRead() async {
    final payload = await _api.post('/notifications/read-all');
    return payload is Map && payload['count'] is num
        ? (payload['count'] as num).toInt()
        : 0;
  }
}
