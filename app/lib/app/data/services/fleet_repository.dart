import 'package:get/get.dart';

import '../models/erp_models.dart' show ErpPage;
import '../models/fleet_models.dart';
import 'api_service.dart';

/// The Fleet app's endpoints (backend routes/erp/fleet.php, `module:fleet`).
///
/// Two audiences read trips: people with fleet.view through /fleet/trips,
/// drivers (fleet.own) through /fleet/my-trips, which only ever holds trips
/// they drive. Methods that serve both take `mine`.
class FleetRepository {
  FleetRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static FleetRepository get to => Get.isRegistered<FleetRepository>()
      ? Get.find<FleetRepository>()
      : Get.put(FleetRepository(Get.find<ApiService>()), permanent: true);

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  String _message(dynamic r) => r is Map ? '${r['message'] ?? ''}' : '';

  Future<FleetOverview> overview() async => FleetOverview.fromJson(_data(await _api.get('/erp/fleet/overview')));

  Future<ErpPage<FleetVehicle>> vehicles({String? q, String? status, int page = 1}) async => ErpPage.fromJson(
    await _map('/erp/fleet/vehicles', {'q': q, 'status': status, 'page': page, 'per_page': 50}),
    FleetVehicle.fromJson,
  );

  Future<FleetVehicle> vehicle(int id) async => FleetVehicle.fromJson(_data(await _api.get('/erp/fleet/vehicles/$id')));

  Future<ErpPage<FleetTrip>> trips({bool mine = false, String? q, String? status, int page = 1}) async => ErpPage.fromJson(
    await _map(mine ? '/erp/fleet/my-trips' : '/erp/fleet/trips', {'q': q, 'status': status, 'page': page, 'per_page': 30}),
    FleetTrip.fromJson,
  );

  Future<FleetTrip> trip(int id, {bool mine = false}) async =>
      FleetTrip.fromJson(_data(await _api.get(mine ? '/erp/fleet/my-trips/$id' : '/erp/fleet/trips/$id')));

  /// Starts a planned trip (fleet.trips). Returns the API's message.
  Future<String> dispatch(int id, {double? odometerOut}) async =>
      _message(await _api.post('/erp/fleet/trips/$id/dispatch', {'odometer_out': ?odometerOut}));

  /// Brings a dispatched trip back (fleet.trips); a company vehicle needs its
  /// odometer reading.
  Future<String> complete(int id, {double? odometerIn}) async =>
      _message(await _api.post('/erp/fleet/trips/$id/complete', {'odometer_in': ?odometerIn}));

  Future<ErpPage<FleetFuel>> fuel({String? q, String? status, int page = 1}) async => ErpPage.fromJson(
    await _map('/erp/fleet/fuel', {'q': q, 'status': status, 'page': page, 'per_page': 30}),
    FleetFuel.fromJson,
  );

  /// Records fuel on a trip; a driver's entry waits for approval. Returns the
  /// API's message ("Recorded. It waits for approval.").
  Future<String> recordFuel(int tripId, FuelDraft draft, {bool mine = false}) async => _message(
    await _api.post(mine ? '/erp/fleet/my-trips/$tripId/fuel' : '/erp/fleet/trips/$tripId/fuel', draft.toJson()),
  );

  /// Approves or rejects a waiting fuel entry (fleet.approve).
  Future<String> decideFuel(int id, {required bool approve, String? reason}) async => _message(
    await _api.post('/erp/fleet/fuel/$id/decision', {
      'decision': approve ? 'approve' : 'reject',
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }),
  );

  /// The accounts and suppliers fuel can be paid from.
  Future<FleetPayLookups> payLookups({bool mine = false}) async =>
      FleetPayLookups.fromJson(_data(await _api.get(mine ? '/erp/fleet/my-trips/lookups' : '/erp/fleet/lookups')));

  /// Schedules, with the ones due or overdue.
  Future<List<FleetSchedule>> schedules() async {
    final payload = await _map('/erp/fleet/schedules');
    return [
      for (final e in (payload['data'] as List? ?? const []).whereType<Map>()) FleetSchedule.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<ErpPage<FleetService>> services({int page = 1}) async =>
      ErpPage.fromJson(await _map('/erp/fleet/services', {'page': page, 'per_page': 30}), FleetService.fromJson);
}
