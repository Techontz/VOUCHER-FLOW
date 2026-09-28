/// Models for company administration: employees, departments, the audit
/// log, voucher types, approval workflows, the company profile and billing.
/// Each mirrors an API resource field for field (see backend
/// app/Http/Resources) and reads leniently, so a missing count is zero
/// rather than a crash.
library;

int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

int? _intOrNull(dynamic value) => value == null ? null : (value is num ? value.toInt() : int.tryParse('$value'));

double? _doubleOrNull(dynamic value) =>
    value == null ? null : (value is num ? value.toDouble() : double.tryParse('$value'));

double _double(dynamic value) => _doubleOrNull(value) ?? 0;

DateTime? _date(dynamic value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

String? _str(dynamic value) => value == null ? null : '$value';

Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : const {};

List<Map<String, dynamic>> _list(dynamic value) =>
    value is List ? [for (final v in value) if (v is Map) Map<String, dynamic>.from(v)] : const [];

/// A Laravel paginated collection: `{data, meta: {current_page, last_page, total}}`.
class Paginated<T> {
  Paginated(this.data, {required this.page, required this.lastPage, required this.total});

  factory Paginated.fromJson(dynamic json, T Function(Map<String, dynamic>) item) {
    final j = _map(json);
    final rows = [for (final r in _list(j['data'])) item(r)];
    final meta = _map(j['meta']);
    return Paginated(
      rows,
      page: _intOrNull(meta['current_page']) ?? 1,
      lastPage: _intOrNull(meta['last_page']) ?? 1,
      total: _intOrNull(meta['total']) ?? rows.length,
    );
  }

  final List<T> data;
  final int page, lastPage, total;
}

/* ─────────────────────────────────────────────────────────── people ── */

/// A person in the company, as the Employees page lists them.
class Employee {
  Employee.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      initials = '${j['initials'] ?? ''}',
      email = '${j['email'] ?? ''}',
      phone = _str(j['phone']),
      role = '${j['role'] ?? 'employee'}',
      roleLabel = '${j['role_label'] ?? j['role'] ?? ''}',
      employeeCode = _str(j['employee_code']),
      jobTitle = _str(j['job_title']),
      status = '${j['status'] ?? 'active'}',
      departmentId = _intOrNull(j['department_id']),
      departmentName = _str(_map(j['department'])['name']),
      voucherCount = _int(j['voucher_count']),
      joinedAt = _date(j['joined_at']);

  final int id;
  final String name, initials, email, role, roleLabel, status;
  final String? phone, employeeCode, jobTitle, departmentName;
  final int? departmentId;
  final int voucherCount;
  final DateTime? joinedAt;
}

/// An active user from `/directory` — who may be named on a department or a
/// workflow level.
class DirectoryUser {
  DirectoryUser.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      role = '${j['role'] ?? ''}',
      jobTitle = _str(j['job_title']),
      departmentId = _intOrNull(j['department_id']);

  final int id;
  final String name, role;
  final String? jobTitle;
  final int? departmentId;
}

/// Someone holding a department's head or manager seat.
class SeatHolder {
  SeatHolder.fromJson(Map<String, dynamic> j) : id = _int(j['id']), name = '${j['name'] ?? ''}', status = _str(j['status']);

  static SeatHolder? maybe(dynamic value) => value is Map ? SeatHolder.fromJson(Map<String, dynamic>.from(value)) : null;

  final int id;
  final String name;
  final String? status;
}

class AdminDepartment {
  AdminDepartment.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      code = _str(j['code']),
      costCentre = _str(j['cost_centre']),
      hodUserId = _intOrNull(j['hod_user_id']),
      managerUserId = _intOrNull(j['manager_user_id']),
      hod = SeatHolder.maybe(j['hod']),
      manager = SeatHolder.maybe(j['manager']),
      usersCount = _int(j['users_count']),
      vouchersCount = _int(j['vouchers_count']),
      spend = _double(j['spend']);

  final int id;
  final String name;
  final String? code, costCentre;
  final int? hodUserId, managerUserId;
  final SeatHolder? hod, manager;
  final int usersCount, vouchersCount;
  final double spend;
}

/* ──────────────────────────────────────────────────────────── audit ── */

class AuditEntry {
  AuditEntry.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      action = '${j['action'] ?? ''}',
      description = '${j['description'] ?? ''}',
      changeSummary = _str(j['change_summary']),
      actorName = '${_map(j['actor'])['name'] ?? 'System'}',
      actorInitials = '${_map(j['actor'])['initials'] ?? ''}',
      company = _str(j['company']),
      ip = _str(j['ip']),
      userAgent = _str(j['user_agent']),
      createdAt = _date(j['created_at']);

  final int id;
  final String action, description, actorName, actorInitials;
  final String? changeSummary, company, ip, userAgent;
  final DateTime? createdAt;

  /// The device column: address, then the first 40 characters of the agent.
  String get device {
    final agent = userAgent;
    final parts = [
      if (ip != null && ip!.isNotEmpty) ip!,
      if (agent != null && agent.isNotEmpty) agent.length > 40 ? agent.substring(0, 40) : agent,
    ];
    return parts.join(' · ');
  }
}

/* ──────────────────────────────────────────────────── voucher types ── */

class AdminVoucherType {
  AdminVoucherType.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      nameSw = _str(j['name_sw']),
      code = '${j['code'] ?? ''}',
      prefix = '${j['prefix'] ?? ''}',
      seqPadding = _intOrNull(j['seq_padding']) ?? 6,
      nextNumber = _intOrNull(j['next_number']) ?? 1,
      resetYearly = j['reset_yearly'] != false,
      isActive = j['is_active'] != false,
      nextNumberPreview = '${j['next_number_preview'] ?? ''}',
      vouchersCount = _int(j['vouchers_count']);

  final int id;
  final String name, code, prefix, nextNumberPreview;
  final String? nameSw;
  final int seqPadding, nextNumber, vouchersCount;
  final bool resetYearly, isActive;

  String label(String locale) => locale == 'sw' && (nameSw ?? '').isNotEmpty ? nameSw! : name;
}

/* ──────────────────────────────────────────────────────── workflows ── */

/// One level of a route. Mutable: the builder edits a copy and sends every
/// stored flag back exactly as loaded unless the editor changed it.
class WorkflowStep {
  WorkflowStep({
    this.id,
    required this.name,
    this.nameSw,
    required this.role,
    this.assignedUserId,
    this.assignedUser,
    this.assigneeHint,
    this.canSign = false,
    this.canApprove = true,
    this.canReject = true,
    this.canRequestChanges = true,
    this.canPay = false,
    this.canPrint = true,
    this.canDownload = true,
    this.requiresSignature = false,
    this.minAmount,
    this.maxAmount,
    this.isRequestStep = false,
  }) : uid = _nextUid++;

  WorkflowStep.fromJson(Map<String, dynamic> j)
    : uid = _nextUid++,
      id = _intOrNull(j['id']),
      name = '${j['name'] ?? ''}',
      nameSw = _str(j['name_sw']),
      role = '${j['role'] ?? 'finance'}',
      assignedUserId = _intOrNull(j['assigned_user_id']),
      assignedUser = SeatHolder.maybe(j['assigned_user']),
      assigneeHint = _str(j['assignee_hint']),
      canSign = j['can_sign'] == true,
      canApprove = j['can_approve'] == true,
      canReject = j['can_reject'] == true,
      canRequestChanges = j['can_request_changes'] == true,
      canPay = j['can_pay'] == true,
      canPrint = j['can_print'] == true,
      canDownload = j['can_download'] == true,
      requiresSignature = j['requires_signature'] == true,
      minAmount = _doubleOrNull(j['min_amount']),
      maxAmount = _doubleOrNull(j['max_amount']),
      isRequestStep = j['is_request_step'] == true;

  static int _nextUid = 1;

  /// A key that survives reordering, for the widgets holding this step.
  final int uid;
  int? id;
  String name;
  String? nameSw;
  String role;
  int? assignedUserId;
  SeatHolder? assignedUser;
  String? assigneeHint;
  bool canSign, canApprove, canReject, canRequestChanges, canPay, canPrint, canDownload;
  bool requiresSignature;
  double? minAmount, maxAmount;
  bool isRequestStep;

  WorkflowStep copy() => WorkflowStep(
    id: id,
    name: name,
    nameSw: nameSw,
    role: role,
    assignedUserId: assignedUserId,
    assignedUser: assignedUser,
    assigneeHint: assigneeHint,
    canSign: canSign,
    canApprove: canApprove,
    canReject: canReject,
    canRequestChanges: canRequestChanges,
    canPay: canPay,
    canPrint: canPrint,
    canDownload: canDownload,
    requiresSignature: requiresSignature,
    minAmount: minAmount,
    maxAmount: maxAmount,
    isRequestStep: isRequestStep,
  );

  bool cap(String key) => switch (key) {
    'can_sign' => canSign,
    'can_approve' => canApprove,
    'can_reject' => canReject,
    'can_request_changes' => canRequestChanges,
    'can_pay' => canPay,
    'can_print' => canPrint,
    'can_download' => canDownload,
    _ => false,
  };

  void setCap(String key, bool value) {
    switch (key) {
      case 'can_sign':
        canSign = value;
      case 'can_approve':
        canApprove = value;
      case 'can_reject':
        canReject = value;
      case 'can_request_changes':
        canRequestChanges = value;
      case 'can_pay':
        canPay = value;
      case 'can_print':
        canPrint = value;
      case 'can_download':
        canDownload = value;
    }
  }

  /// A level chooses its person by name when it is "custom" or names someone.
  bool get isPersonMode => role == 'custom' || assignedUserId != null;
}

class Workflow {
  Workflow({
    required this.id,
    required this.name,
    this.nameSw,
    this.description,
    this.voucherTypeId,
    this.voucherTypeName,
    this.voucherTypeNameSw,
    this.isDefault = false,
    this.isActive = true,
    this.version = 1,
    this.routeSummary,
    this.steps = const [],
    this.vouchersCount = 0,
    this.inFlightCount = 0,
  });

  Workflow.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      nameSw = _str(j['name_sw']),
      description = _str(j['description']),
      voucherTypeId = _intOrNull(j['voucher_type_id']),
      voucherTypeName = _str(_map(j['voucher_type'])['name']),
      voucherTypeNameSw = _str(_map(j['voucher_type'])['name_sw']),
      isDefault = j['is_default'] == true,
      isActive = j['is_active'] != false,
      version = _intOrNull(j['version']) ?? 1,
      routeSummary = _str(j['route_summary']),
      steps = [for (final s in _list(j['steps'])) WorkflowStep.fromJson(s)],
      vouchersCount = _int(j['vouchers_count']),
      inFlightCount = _int(j['in_flight_count']);

  final int id;
  String name;
  String? nameSw, description;
  int? voucherTypeId;
  String? voucherTypeName, voucherTypeNameSw;
  bool isDefault, isActive;
  final int version;
  final String? routeSummary;
  final List<WorkflowStep> steps;
  final int vouchersCount, inFlightCount;

  Workflow copy() => Workflow(
    id: id,
    name: name,
    nameSw: nameSw,
    description: description,
    voucherTypeId: voucherTypeId,
    voucherTypeName: voucherTypeName,
    voucherTypeNameSw: voucherTypeNameSw,
    isDefault: isDefault,
    isActive: isActive,
    version: version,
    routeSummary: routeSummary,
    steps: steps,
    vouchersCount: vouchersCount,
    inFlightCount: inFlightCount,
  );

  String? typeLabel(String locale) =>
      voucherTypeName == null ? null : (locale == 'sw' && (voucherTypeNameSw ?? '').isNotEmpty ? voucherTypeNameSw : voucherTypeName);
}

/// The body the builder sends when it saves — the web's workflowPayload():
/// every flag the backend stores goes back exactly as it was loaded unless
/// the person editing changed it (a missing `can_pay` once stripped payment
/// from every step).
Map<String, dynamic> workflowPayload(Workflow workflow, List<WorkflowStep> steps, {bool includeIds = true}) => {
  'name': workflow.name,
  'name_sw': (workflow.nameSw ?? '').isEmpty ? null : workflow.nameSw,
  'voucher_type_id': workflow.voucherTypeId,
  'description': workflow.description,
  'is_default': workflow.isDefault,
  'is_active': workflow.isActive,
  'steps': [
    for (var i = 0; i < steps.length; i++)
      {
        'id': includeIds ? steps[i].id : null,
        'position': i + 1,
        'name': steps[i].name,
        'name_sw': steps[i].nameSw,
        'role': steps[i].role,
        'assigned_user_id': steps[i].assignedUserId,
        'assignee_hint': steps[i].assigneeHint,
        'can_sign': steps[i].canSign,
        'can_approve': steps[i].canApprove,
        'can_reject': steps[i].canReject,
        'can_request_changes': steps[i].canRequestChanges,
        'can_pay': steps[i].canPay,
        'can_print': steps[i].canPrint,
        'can_download': steps[i].canDownload,
        'requires_signature': steps[i].requiresSignature,
        'min_amount': steps[i].minAmount,
        'max_amount': steps[i].maxAmount,
      },
  ],
};

class WorkflowPreset {
  WorkflowPreset.fromJson(Map<String, dynamic> j)
    : key = '${j['key'] ?? ''}',
      name = '${j['name'] ?? ''}',
      description = '${j['description'] ?? ''}';

  final String key, name, description;
}

/// Who a saved workflow resolves to, department by department.
class WorkflowRouting {
  WorkflowRouting.fromJson(Map<String, dynamic> j)
    : steps = [for (final s in _list(j['steps'])) RoutingStep.fromJson(s)],
      departments = [for (final d in _list(j['departments'])) RoutingDepartment.fromJson(d)],
      gaps = _int(j['gaps']);

  final List<RoutingStep> steps;
  final List<RoutingDepartment> departments;
  final int gaps;
}

class RoutingStep {
  RoutingStep.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      nameSw = _str(j['name_sw']),
      isRequestStep = j['is_request_step'] == true;

  final int id;
  final String name;
  final String? nameSw;
  final bool isRequestStep;

  String label(String locale) => locale == 'sw' && (nameSw ?? '').isNotEmpty ? nameSw! : name;
}

class RoutingDepartment {
  RoutingDepartment.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      cells = [for (final c in _list(j['cells'])) RoutingCell.fromJson(c)];

  final int id;
  final String name;
  final List<RoutingCell> cells;
}

class RoutingCell {
  RoutingCell.fromJson(Map<String, dynamic> j)
    : stepId = _int(j['step_id']),
      people = [for (final p in _list(j['people'])) '${p['name'] ?? ''}'],
      gap = _str(j['gap']);

  final int stepId;
  final List<String> people;
  final String? gap;
}

/* ──────────────────────────────────────────────────── the company ── */

/// The company's full profile from GET /company — everything the settings
/// and branding pages edit (the session's Company keeps only what the rest
/// of the app reads).
class CompanyProfile {
  CompanyProfile.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      legalName = _str(j['legal_name']),
      email = '${j['email'] ?? ''}',
      phone = _str(j['phone']),
      address = _str(j['address']),
      website = _str(j['website']),
      tin = _str(j['tin']),
      currency = '${j['currency'] ?? 'TZS'}',
      locale = '${j['locale'] ?? 'en'}',
      timezone = _str(j['timezone']),
      primaryColor = _str(j['primary_color']),
      secondaryColor = _str(j['secondary_color']),
      colorTheme = '${j['color_theme'] ?? 'blue'}',
      voucherFooterText = _str(j['voucher_footer_text']),
      voucherTemplate = '${j['voucher_template'] ?? 'classic'}',
      bankName = _str(j['bank_name']),
      bankBranch = _str(j['bank_branch']),
      bankAccountName = _str(j['bank_account_name']),
      bankAccountNumber = _str(j['bank_account_number']),
      logoUrl = _str(j['logo_url']),
      logoMarkUrl = _str(j['logo_mark_url']);

  final int id;
  final String name, email, currency, locale, colorTheme, voucherTemplate;
  final String? legalName, phone, address, website, tin, timezone;
  final String? primaryColor, secondaryColor, voucherFooterText;
  final String? bankName, bankBranch, bankAccountName, bankAccountNumber;
  final String? logoUrl, logoMarkUrl;
}

/* ─────────────────────────────────────────────────────────── billing ── */

class BillingPlan {
  BillingPlan.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      price = _double(j['price']),
      currency = '${j['currency'] ?? 'TZS'}',
      maxUsers = _intOrNull(j['max_users']),
      maxVouchersPerMonth = _intOrNull(j['max_vouchers_per_month']),
      maxApprovalLevels = _intOrNull(j['max_approval_levels']);

  final int id;
  final String name, currency;
  final double price;
  final int? maxUsers, maxVouchersPerMonth, maxApprovalLevels;
}

class UsageMetric {
  UsageMetric.fromJson(Map<String, dynamic> j)
    : label = '${j['label'] ?? ''}',
      used = _int(j['used']),
      limit = _intOrNull(j['limit']),
      unit = '${j['unit'] ?? ''}',
      unlimited = j['unlimited'] == true || j['limit'] == null,
      percent = _intOrNull(j['percent']),
      exceeded = j['exceeded'] == true;

  final String label, unit;
  final int used;
  final int? limit, percent;
  final bool unlimited, exceeded;
}

class BillingSubscription {
  BillingSubscription.fromJson(Map<String, dynamic> j)
    : billingCycle = '${j['billing_cycle'] ?? 'monthly'}',
      amount = _double(j['amount']),
      currency = '${j['currency'] ?? 'TZS'}';

  final String billingCycle, currency;
  final double amount;
}

/// GET /billing/subscription.
class BillingState {
  BillingState.fromJson(Map<String, dynamic> j)
    : subscription = j['subscription'] is Map ? BillingSubscription.fromJson(_map(j['subscription'])) : null,
      plan = j['plan'] is Map ? BillingPlan.fromJson(_map(j['plan'])) : null,
      users = UsageMetric.fromJson(_map(_map(j['usage'])['users'])),
      vouchersThisMonth = UsageMetric.fromJson(_map(_map(j['usage'])['vouchers_this_month'])),
      departments = UsageMetric.fromJson(_map(_map(j['usage'])['departments'])),
      storage = UsageMetric.fromJson(_map(_map(j['usage'])['storage'])),
      companyStatus = '${j['company_status'] ?? ''}',
      isExpired = j['is_expired'] == true,
      daysRemaining = _intOrNull(j['days_remaining']),
      autoRenew = j['auto_renew'] == true,
      availablePlans = [for (final p in _list(j['available_plans'])) BillingPlan.fromJson(p)];

  final BillingSubscription? subscription;
  final BillingPlan? plan;
  final UsageMetric users, vouchersThisMonth, departments, storage;
  final String companyStatus;
  final bool isExpired, autoRenew;
  final int? daysRemaining;
  final List<BillingPlan> availablePlans;

  List<UsageMetric> get metrics => [users, vouchersThisMonth, departments, storage];
}

class Invoice {
  Invoice.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      number = '${j['number'] ?? ''}',
      description = '${j['description'] ?? ''}',
      amountText = '${j['amount_text'] ?? ''}',
      status = '${j['status'] ?? ''}',
      methodLabel = '${j['method_label'] ?? '—'}',
      providerRef = _str(j['provider_ref']),
      failureReason = _str(j['failure_reason']),
      issuedAt = _date(j['issued_at']),
      paidAt = _date(j['paid_at']);

  final int id;
  final String number, description, amountText, status, methodLabel;
  final String? providerRef, failureReason;
  final DateTime? issuedAt, paidAt;

  bool get payable => status == 'pending' || status == 'failed';
}
