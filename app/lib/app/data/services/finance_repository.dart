import 'package:get/get.dart';

import '../models/erp_models.dart';
import '../models/finance_models.dart';
import 'api_service.dart';

/// The Finance app's endpoints (backend routes/erp/finance.php under
/// `module:accounting`, and the core journals and trial balance): the cash
/// position, bank accounts, the cashbook, journals and the statements.
class FinanceRepository {
  FinanceRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static FinanceRepository get to => Get.isRegistered<FinanceRepository>()
      ? Get.find<FinanceRepository>()
      : Get.put(FinanceRepository(Get.find<ApiService>()), permanent: true);

  static const _base = '/erp/finance';

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  Map<String, dynamic> _data(dynamic payload) => Map<String, dynamic>.from((payload as Map)['data'] as Map);

  Future<FinanceOverview> overview() async => FinanceOverview.fromJson(_data(await _api.get('$_base/overview')));

  /* ── bank and cash accounts ── */

  Future<List<BankAccount>> bankAccounts() async {
    final payload = await _map('$_base/bank-accounts');
    return ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => BankAccount.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// The account with its ledger statement for [from]..[to] (the API's
  /// default when null: the last three months).
  Future<BankAccount> bankAccount(int id, {DateTime? from, DateTime? to}) async =>
      BankAccount.fromJson(_data(await _api.get('$_base/bank-accounts/$id', {'from': day(from), 'to': day(to)})));

  /* ── cashbook ── */

  Future<CashbookPage> cashbook({String? type, String? status, String? q, int page = 1}) async =>
      CashbookPage.fromJson(
        await _map('$_base/cashbook', {'type': type, 'status': status, 'q': q, 'page': page}),
      );

  Future<CashbookEntry> cashbookEntry(int id) async =>
      CashbookEntry.fromJson(_data(await _api.get('$_base/cashbook/$id')));

  /// The ledger accounts a receipt or payment may go to (not cash or bank).
  Future<List<LedgerAccount>> cashbookAccounts() async {
    final payload = await _map('$_base/cashbook/accounts');
    return ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => LedgerAccount.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Saves a draft; nothing reaches the ledger until it is posted.
  Future<CashbookEntry> createCashbookEntry(CashbookDraft draft) async =>
      CashbookEntry.fromJson(_data(await _api.post('$_base/cashbook', draft.toJson())));

  Future<String> postCashbookEntry(int id) async =>
      '${(await _api.post('$_base/cashbook/$id/post') as Map)['message'] ?? ''}';

  Future<void> cancelCashbookEntry(int id) => _api.post('$_base/cashbook/$id/cancel');

  /* ── journals and reports ── */

  Future<ErpPage<JournalEntry>> journals({String? q, String? sourceType, int page = 1}) async => ErpPage.fromJson(
    await _map('/erp/journals', {'q': q, 'source_type': sourceType, 'page': page}),
    JournalEntry.fromJson,
  );

  Future<JournalEntry> journal(int id) async => JournalEntry.fromJson(_data(await _api.get('/erp/journals/$id')));

  Future<TrialBalance> trialBalance({DateTime? from, DateTime? to}) async =>
      TrialBalance.fromJson(_data(await _api.get('/erp/trial-balance', {'from': day(from), 'to': day(to)})));

  Future<ProfitAndLoss> profitAndLoss({DateTime? from, DateTime? to}) async => ProfitAndLoss.fromJson(
    _data(await _api.get('$_base/statements/profit-and-loss', {'from': day(from), 'to': day(to)})),
  );

  Future<BalanceSheet> balanceSheet({DateTime? asOf}) async =>
      BalanceSheet.fromJson(_data(await _api.get('$_base/statements/balance-sheet', {'as_of': day(asOf)})));

  Future<BudgetVsActual> budgetVsActual({int? year}) async =>
      BudgetVsActual.fromJson(_data(await _api.get('$_base/statements/budget-vs-actual', {'year': year})));

  /// "2026-11-12", the API's date.
  static String? day(DateTime? d) =>
      d == null ? null : '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
}
