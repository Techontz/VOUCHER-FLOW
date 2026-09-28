/// Models for the voucher register and the create/edit voucher screens —
/// the parts of the API payloads the shared models do not carry.
library;

import 'models.dart';

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double? _numOrNull(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
String? _str(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';

/// A voucher type as the create screen needs it: with its `code`, which
/// decides the icon, tone and description the web draws for it.
class VoucherTypeOption {
  VoucherTypeOption.fromJson(Map<String, dynamic> json)
    : id = _int(json['id']),
      code = '${json['code'] ?? ''}',
      name = '${json['name'] ?? ''}',
      label = '${json['label'] ?? json['name'] ?? ''}',
      nextNumberPreview = '${json['next_number_preview'] ?? ''}';

  final int id;
  final String code, name, label, nextNumberPreview;
}

/// One voucher in the register, with the fields the list row reads that the
/// shared [Voucher] model leaves out (last update, who decided, the role at
/// the current step, the payment date).
class RegisterRow {
  RegisterRow.fromJson(Map<String, dynamic> json)
    : voucher = Voucher.fromJson(json),
      updatedAt = _date(json['updated_at']),
      paymentDate = _date(json['payment_date']),
      decidedBy = _str(json['decided_by']),
      stepRole = json['current_step'] is Map ? _str((json['current_step'] as Map)['role']) : null;

  final Voucher voucher;
  final DateTime? updatedAt, paymentDate;
  final String? decidedBy, stepRole;
}

/// One page of `GET /vouchers` with its meta.
class RegisterPage {
  RegisterPage.fromJson(Map<String, dynamic> json)
    : rows = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => RegisterRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total = _int((json['meta'] as Map?)?['total'] ?? (json['data'] as List?)?.length ?? 0),
      totalAmount = _numOrNull((json['meta'] as Map?)?['total_amount']),
      currency = _str((json['meta'] as Map?)?['currency']),
      currentPage = (json['meta'] as Map?)?['current_page'] == null ? 1 : _int((json['meta'] as Map)['current_page']),
      lastPage = (json['meta'] as Map?)?['last_page'] == null ? 1 : _int((json['meta'] as Map)['last_page']);

  final List<RegisterRow> rows;
  final int total, currentPage, lastPage;
  final double? totalAmount;
  final String? currency;
}

/// One step of a company workflow (`WorkflowStepResource`).
class RouteStep {
  RouteStep.fromJson(Map<String, dynamic> json)
    : position = _int(json['position']),
      role = '${json['role'] ?? ''}',
      roleLabel = _str(json['role_label']),
      name = '${json['name'] ?? ''}',
      nameSw = _str(json['name_sw']),
      canPay = json['can_pay'] == true,
      canApprove = json['can_approve'] == true,
      minAmount = _numOrNull(json['min_amount']),
      maxAmount = _numOrNull(json['max_amount']);

  final int position;
  final String role, name;
  final String? roleLabel, nameSw;
  final bool canPay, canApprove;
  final double? minAmount, maxAmount;

  /// WorkflowStep::isRequestStep — the step that raises the voucher.
  bool get isRequest => position == 1 || role == 'employee';

  /// WorkflowStep::appliesToAmount — thresholds, both ends inclusive.
  bool appliesTo(double amount) {
    if (minAmount != null && amount < minAmount!) return false;
    if (maxAmount != null && amount > maxAmount!) return false;
    return true;
  }
}

/// A company workflow (`WorkflowResource`), for the review step's route.
class RouteWorkflow {
  RouteWorkflow.fromJson(Map<String, dynamic> json)
    : id = _int(json['id']),
      voucherTypeId = json['voucher_type_id'] == null ? null : _int(json['voucher_type_id']),
      isDefault = json['is_default'] == true,
      isActive = json['is_active'] == true,
      steps = (json['steps'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => RouteStep.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  final int id;
  final int? voucherTypeId;
  final bool isDefault, isActive;
  final List<RouteStep> steps;
}

/// WorkflowEngine::resolveWorkflow — which route a new voucher of this type
/// takes: active only; bound to the type beats general; the default wins.
RouteWorkflow? resolveWorkflow(List<RouteWorkflow> workflows, int? voucherTypeId) {
  final candidates = workflows
      .where((w) => w.isActive && (w.voucherTypeId == voucherTypeId || w.voucherTypeId == null))
      .toList();
  candidates.sort((a, b) {
    final ta = a.voucherTypeId == null ? 1 : 0;
    final tb = b.voucherTypeId == null ? 1 : 0;
    if (ta != tb) return ta - tb;
    return (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0);
  });
  return candidates.isEmpty ? null : candidates.first;
}

/// The steps a voucher of this amount passes through after it is raised.
List<String> routeFor(RouteWorkflow? workflow, double amount, {bool sw = false}) {
  if (workflow == null) return const [];
  final steps = [...workflow.steps]..sort((a, b) => a.position.compareTo(b.position));
  return steps
      .where((s) => s.isRequest || s.appliesTo(amount))
      .where((s) => !s.isRequest)
      .map((s) => sw && s.nameSw != null ? s.nameSw! : (s.roleLabel ?? s.name))
      .toList();
}

/// The server's words for an amount, mirrored so the preview matches the PDF
/// ("Four hundred Fifty thousand shillings only").
String amountInWords(double amount, String currency) {
  const units = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', //
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  const majors = {'TZS': 'shillings', 'KES': 'shillings', 'USD': 'dollars', 'EUR': 'euros', 'GBP': 'pounds'};

  String under(int n) {
    if (n < 20) return units[n];
    if (n < 100) return tens[n ~/ 10] + (n % 10 != 0 ? '-${units[n % 10]}' : '');
    return '${units[n ~/ 100]} hundred${n % 100 != 0 ? ' ${under(n % 100)}' : ''}';
  }

  final major = majors[currency] ?? 'units';
  final whole = amount.abs().floor();
  final cents = ((amount.abs() - whole) * 100).round();
  if (whole == 0 && cents == 0) return 'Zero $major only';

  final parts = <String>[];
  var rest = whole;
  for (final (value, label) in const [(1000000000, 'billion'), (1000000, 'million'), (1000, 'thousand')]) {
    if (rest >= value) {
      parts.add('${under(rest ~/ value)} $label');
      rest %= value;
    }
  }
  if (rest > 0) parts.add(under(rest));

  var text = '${parts.isEmpty ? 'Zero' : parts.join(' ')} $major';
  if (cents > 0) text += ' and ${under(cents)} cents';
  return '$text only';
}

/// Parses a typed amount the way the web does: digits and the point only.
double parseAmount(String text) => _num(text.replaceAll(RegExp(r'[^0-9.]'), ''));
