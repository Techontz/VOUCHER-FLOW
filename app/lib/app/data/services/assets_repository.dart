import 'package:get/get.dart';

import '../models/erp_models.dart';
import '../models/finance_models.dart';
import 'api_service.dart';

/// The Assets app's endpoints (backend routes/erp/finance.php under
/// `module:assets`): the register, each asset's history and schedule, and
/// the monthly depreciation runs.
class AssetsRepository {
  AssetsRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static AssetsRepository get to => Get.isRegistered<AssetsRepository>()
      ? Get.find<AssetsRepository>()
      : Get.put(AssetsRepository(Get.find<ApiService>()), permanent: true);

  static const _base = '/erp/assets';

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  Future<AssetsOverview> overview() async => AssetsOverview.fromJson(_data(await _api.get('$_base/overview')));

  Future<ErpPage<FixedAsset>> register({String? status, String? q, int page = 1}) async => ErpPage.fromJson(
    Map<String, dynamic>.from(await _api.get('$_base/register', {'status': status, 'q': q, 'page': page}) as Map),
    FixedAsset.fromJson,
  );

  Future<FixedAsset> asset(int id) async => FixedAsset.fromJson(_data(await _api.get('$_base/register/$id')));

  Future<ErpPage<DepreciationRun>> runs({int page = 1}) async => ErpPage.fromJson(
    Map<String, dynamic>.from(await _api.get('$_base/depreciation', {'page': page}) as Map),
    DepreciationRun.fromJson,
  );

  Future<DepreciationRun> run(int id) async => DepreciationRun.fromJson(_data(await _api.get('$_base/depreciation/$id')));
}
