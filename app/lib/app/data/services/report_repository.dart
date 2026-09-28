import 'dart:typed_data';

import 'package:get/get.dart';

import '../models/models.dart';
import '../models/report_models.dart';
import 'api_service.dart';

/// The reports screen's calls. Every report is built server-side through the
/// same visibility rules as the voucher list, so neither the screen nor an
/// export can hold more than the caller may see.
class ReportRepository {
  ReportRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static ReportRepository get instance => Get.isRegistered<ReportRepository>()
      ? Get.find<ReportRepository>()
      : Get.put(ReportRepository(Get.find<ApiService>()), permanent: true);

  List<Map<String, dynamic>> _data(dynamic payload) =>
      (((payload as Map)['data'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  /// The reports this role may run, and how far its reporting reaches.
  Future<ReportCatalogue> catalogue() async {
    final payload = await _api.get('/reports') as Map;
    final scope = payload['scope'];
    return ReportCatalogue(
      _data(payload).map(ReportKind.fromJson).toList(),
      scope is Map ? ReportScope.fromJson(scope.cast<String, dynamic>()) : null,
    );
  }

  Future<ReportResult> show(String kind, Map<String, String> params) async =>
      ReportResult.fromJson(
        ((await _api.get('/reports/$kind', params)) as Map).cast<String, dynamic>(),
      );

  /// The report as a file: pdf, xlsx or csv, built from exactly these filters.
  Future<Uint8List> export(String kind, Map<String, String> params, String format) async =>
      Uint8List.fromList(
        await _api.bytes('/reports/$kind/export', {...params, 'format': format}),
      );

  Future<List<Department>> departments() async =>
      _data(await _api.get('/departments')).map(Department.fromJson).toList();

  Future<List<VoucherType>> voucherTypes() async =>
      _data(await _api.get('/voucher-types')).map(VoucherType.fromJson).toList();

  Future<List<ReportPerson>> people() async =>
      _data(await _api.get('/directory')).map(ReportPerson.fromJson).toList();
}
