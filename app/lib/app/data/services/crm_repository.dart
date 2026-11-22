import 'package:get/get.dart';

import '../models/erp_models.dart' show ErpPage;
import '../models/ops_models.dart';
import 'api_service.dart';

/// The CRM app's endpoints (backend routes/erp/crm.php, `module:crm`):
/// the overview, the pipeline board, leads, opportunities and activities.
/// The API narrows every list to the caller's own records unless they hold
/// crm.view_all.
class CrmRepository {
  CrmRepository(this._api);

  final ApiService _api;

  static CrmRepository get to => Get.isRegistered<CrmRepository>()
      ? Get.find<CrmRepository>()
      : Get.put(CrmRepository(Get.find<ApiService>()), permanent: true);

  static const _base = '/erp/crm';

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  Future<CrmOverview> overview() async => CrmOverview.fromJson(_data(await _api.get('$_base/overview')));

  /// Every deal grouped by stage; closed ones from the last 90 days.
  Future<List<CrmStageTotal>> board() async {
    final payload = await _map('$_base/opportunities/board');
    return ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => CrmStageTotal.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<CrmOpportunity> opportunity(int id) async =>
      CrmOpportunity.fromJson(_data(await _api.get('$_base/opportunities/$id')));

  /// Moves a deal; [reason] is required to close it as lost.
  Future<String> moveStage(int id, String stage, {String? reason, String? note}) async {
    final r = await _api.post('$_base/opportunities/$id/stage', {
      'stage': stage,
      'reason': ?reason,
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
    });
    return r is Map ? '${r['message'] ?? ''}' : '';
  }

  Future<ErpPage<CrmLead>> leads({String? status, String? q, int page = 1}) async =>
      ErpPage.fromJson(await _map('$_base/leads', {'status': status, 'q': q, 'page': page, 'per_page': 30}), CrmLead.fromJson);

  Future<CrmLead> lead(int id) async => CrmLead.fromJson(_data(await _api.get('$_base/leads/$id')));

  Future<CrmLead> createLead(CrmLeadDraft draft) async =>
      CrmLead.fromJson(_data(await _api.post('$_base/leads', draft.toJson())));

  /// Changes a lead's status; [lostReason] is needed for 'lost'.
  Future<CrmLead> setLeadStatus(int id, String status, {String? lostReason}) async => CrmLead.fromJson(
    _data(await _api.put('$_base/leads/$id', {'status': status, if ((lostReason ?? '').trim().isNotEmpty) 'lost_reason': lostReason!.trim()})),
  );

  /// [status]: 'open' | 'today' | 'overdue' | 'done' | null.
  Future<ErpPage<CrmActivity>> activities({String? status, String? type, int page = 1}) async => ErpPage.fromJson(
    await _map('$_base/activities', {'status': status, 'type': type, 'page': page, 'per_page': 30}),
    CrmActivity.fromJson,
  );

  /// Logs an activity; one that already happened is completed at once with
  /// its outcome, as the web's "Mark done" does.
  Future<CrmActivity> log(CrmActivityDraft draft) async {
    final created = CrmActivity.fromJson(_data(await _api.post('$_base/activities', draft.toJson())));
    if (draft.done) await complete(created.id, draft.outcome);
    return created;
  }

  Future<void> complete(int id, [String? outcome]) =>
      _api.post('$_base/activities/$id/complete', {if ((outcome ?? '').trim().isNotEmpty) 'outcome': outcome!.trim()});

  Future<void> reopen(int id) => _api.post('$_base/activities/$id/reopen');
}
