/// Models used by the voucher page, bulk approval and the payment queue.
library;

import 'models.dart';

double _num(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

double? _numOrNull(dynamic value) =>
    value == null ? null : (value is num ? value.toDouble() : double.tryParse('$value'));

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

/// One page of `/vouchers`, with the list's own totals.
class VoucherPage {
  VoucherPage.fromJson(Map<String, dynamic> json)
    : data = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Voucher.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total = _int((json['meta'] as Map?)?['total'] ?? (json['data'] as List?)?.length),
      currentPage = _int((json['meta'] as Map?)?['current_page'] ?? 1),
      lastPage = _int((json['meta'] as Map?)?['last_page'] ?? 1),
      totalAmount = _num((json['meta'] as Map?)?['total_amount']),
      totalBalance = _numOrNull((json['meta'] as Map?)?['total_balance']);

  final List<Voucher> data;
  final int total, currentPage, lastPage;
  final double totalAmount;

  /// What is still owed across the matching vouchers, part payments deducted.
  final double? totalBalance;
}

/// A step of a company workflow, as `/workflows` returns it.
class WorkflowStepInfo {
  WorkflowStepInfo.fromJson(Map<String, dynamic> json)
    : position = _int(json['position']),
      name = '${json['name'] ?? ''}',
      nameSw = json['name_sw'] as String?,
      role = '${json['role'] ?? ''}',
      roleLabel = json['role_label'] as String?,
      canApprove = json['can_approve'] == true,
      canPay = json['can_pay'] == true,
      minAmount = _numOrNull(json['min_amount']),
      maxAmount = _numOrNull(json['max_amount']);

  final int position;
  final String name, role;
  final String? nameSw, roleLabel;
  final bool canApprove, canPay;
  final double? minAmount, maxAmount;

  /// WorkflowStep::isRequestStep.
  bool get isRequestStep => position == 1 || role == 'employee';

  /// WorkflowStep::isPaymentStep.
  bool get isPaymentStep => canPay && !canApprove;

  bool appliesTo(double amount) {
    if (minAmount != null && amount < minAmount!) return false;
    if (maxAmount != null && amount > maxAmount!) return false;
    return true;
  }

  String label(String locale) =>
      locale == 'sw' && (nameSw ?? '').isNotEmpty
      ? nameSw!
      : ((roleLabel ?? '').isNotEmpty ? roleLabel! : name);
}

class WorkflowInfo {
  WorkflowInfo.fromJson(Map<String, dynamic> json)
    : id = _int(json['id']),
      steps = (json['steps'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkflowStepInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  final int id;
  final List<WorkflowStepInfo> steps;
}

/// The result of `/vouchers/bulk-approve`.
class BulkApproveResult {
  BulkApproveResult.fromJson(Map<String, dynamic> json)
    : approved = (json['approved'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => '${e['number'] ?? '#${e['id']}'}')
          .toList(),
      skipped = (json['skipped'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => '${e['number'] ?? '#${e['id']}'}: ${e['reason'] ?? ''}')
          .toList();

  final List<String> approved;
  final List<String> skipped;
}
