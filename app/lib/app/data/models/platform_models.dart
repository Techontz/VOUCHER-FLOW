// The platform super admin's view of the tenants: companies, plans, invoices,
// users and the per-company insight endpoints (Platform\CompanyController,
// CompanyInsightController, PlanController, PaymentController,
// UserController). Shapes follow the API resources exactly.

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _numOrNull(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _list(Object? v) => [
  for (final e in (v is List ? v : const [])) _map(e),
];

/// Initials as the web derives them when the API sends none.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  return words.map((w) => w[0].toUpperCase()).join();
}

/// A page of results with Laravel's pagination meta (plus any extra totals).
class PlatformPage<T> {
  PlatformPage({required this.items, required this.page, required this.lastPage, required this.total, this.meta = const {}});

  factory PlatformPage.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    final meta = _map(json['meta']);
    final items = [for (final e in _list(json['data'])) parse(e)];
    return PlatformPage(
      items: items,
      page: _intOrNull(meta['current_page']) ?? 1,
      lastPage: _intOrNull(meta['last_page']) ?? 1,
      total: _intOrNull(meta['total']) ?? items.length,
      meta: meta,
    );
  }

  final List<T> items;
  final int page;
  final int lastPage;
  final int total;
  final Map<String, dynamic> meta;

  double metaNum(String key) => _num(meta[key]);
}

class PlatformPlan {
  PlatformPlan.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      code = '${j['code'] ?? ''}',
      name = '${j['name'] ?? ''}',
      blurb = _str(j['blurb']),
      price = _num(j['price']),
      currency = '${j['currency'] ?? 'TZS'}',
      billingCycle = '${j['billing_cycle'] ?? 'monthly'}',
      maxUsers = _intOrNull(j['max_users']),
      maxVouchersPerMonth = _intOrNull(j['max_vouchers_per_month']),
      maxDepartments = _intOrNull(j['max_departments']),
      maxApprovalLevels = _intOrNull(j['max_approval_levels']),
      storageMb = _intOrNull(j['storage_mb']),
      trialDays = _int(j['trial_days']),
      isActive = j['is_active'] != false,
      isPublic = j['is_public'] != false,
      sortOrder = _int(j['sort_order']),
      companiesCount = _int(j['companies_count']);

  final int id;
  final String code, name;
  final String? blurb;
  final double price;
  final String currency, billingCycle;
  final int? maxUsers, maxVouchersPerMonth, maxDepartments, maxApprovalLevels, storageMb;
  final int trialDays;
  final bool isActive, isPublic;
  final int sortOrder;
  final int companiesCount;
}

class PlatformCompany {
  PlatformCompany.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      initials = _str(j['initials']),
      legalName = _str(j['legal_name']),
      tradingName = _str(j['trading_name']),
      email = _str(j['email']),
      phone = _str(j['phone']),
      alternativePhone = _str(j['alternative_phone']),
      website = _str(j['website']),
      address = _str(j['address']),
      postalAddress = _str(j['postal_address']),
      city = _str(j['city']),
      region = _str(j['region']),
      country = _str(j['country']),
      tin = _str(j['tin']),
      registrationNumber = _str(j['registration_number']),
      businessLicenseNumber = _str(j['business_license_number']),
      contactPerson = _str(j['contact_person']),
      contactEmail = _str(j['contact_email']),
      contactPhone = _str(j['contact_phone']),
      currency = _str(j['currency']),
      locale = _str(j['locale']),
      timezone = _str(j['timezone']),
      logoUrl = _str(j['logo_url']),
      logoMarkUrl = _str(j['logo_mark_url']),
      primaryColor = _str(j['primary_color']),
      secondaryColor = _str(j['secondary_color']),
      accentColor = _str(j['accent_color']),
      theme = '${j['theme'] ?? 'light'}',
      colorTheme = _str(j['color_theme']) ?? 'blue',
      voucherHeaderText = _str(j['voucher_header_text']),
      voucherFooterText = _str(j['voucher_footer_text']),
      bankName = _str(j['bank_name']),
      bankBranch = _str(j['bank_branch']),
      bankAccountName = _str(j['bank_account_name']),
      bankAccountNumber = _str(j['bank_account_number']),
      swiftCode = _str(j['swift_code']),
      status = '${j['status'] ?? ''}',
      daysRemaining = _intOrNull(j['days_remaining']),
      trialEndsAt = _date(j['trial_ends_at']),
      currentPeriodStart = _date(j['current_period_start']),
      currentPeriodEnd = _date(j['current_period_end']),
      autoRenew = j['auto_renew'] == true,
      plan = j['plan'] is Map ? PlatformPlan.fromJson(_map(j['plan'])) : null,
      planId = _intOrNull(j['plan_id']),
      usersCount = _int(j['users_count']),
      vouchersCount = _int(j['vouchers_count']),
      createdAt = _date(j['created_at']);

  final int id;
  final String name;
  final String? initials, legalName, tradingName, email, phone, alternativePhone, website, address, postalAddress;
  final String? city, region, country, tin, registrationNumber, businessLicenseNumber;
  final String? contactPerson, contactEmail, contactPhone, currency, locale, timezone;
  final String? logoUrl, logoMarkUrl, primaryColor, secondaryColor, accentColor;
  final String theme, colorTheme;
  final String? voucherHeaderText, voucherFooterText;
  final String? bankName, bankBranch, bankAccountName, bankAccountNumber, swiftCode;
  final String status;
  final int? daysRemaining;
  final DateTime? trialEndsAt, currentPeriodStart, currentPeriodEnd;
  final bool autoRenew;
  final PlatformPlan? plan;
  final int? planId;
  final int usersCount, vouchersCount;
  final DateTime? createdAt;

  String get displayInitials => initials ?? initialsOf(name);

  /// Trial companies renew at the trial's end; everyone else at the period end.
  DateTime? get renewsAt => status == 'trial' ? trialEndsAt : currentPeriodEnd;
}

class PlatformUser {
  PlatformUser.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      companyId = _intOrNull(j['company_id']),
      name = '${j['name'] ?? ''}',
      initials = _str(j['initials']),
      email = '${j['email'] ?? ''}',
      phone = _str(j['phone']),
      role = '${j['role'] ?? ''}',
      roleLabel = '${j['role_label'] ?? j['role'] ?? ''}',
      jobTitle = _str(j['job_title']),
      status = '${j['status'] ?? ''}',
      departmentName = _str(_map(j['department'])['name']),
      voucherCount = _int(j['voucher_count']),
      lastLoginAt = _date(j['last_login_at']),
      joinedAt = _date(j['joined_at']);

  final int id;
  final int? companyId;
  final String name;
  final String? initials;
  final String email;
  final String? phone;
  final String role, roleLabel;
  final String? jobTitle;
  final String status;
  final String? departmentName;
  final int voucherCount;
  final DateTime? lastLoginAt, joinedAt;

  String get displayInitials => initials ?? initialsOf(name);
}

class PlatformInvoice {
  PlatformInvoice.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      number = '${j['number'] ?? ''}',
      description = '${j['description'] ?? ''}',
      amountText = '${j['amount_text'] ?? ''}',
      status = '${j['status'] ?? ''}',
      statusTag = '${j['status_tag'] ?? 'tag-neutral'}',
      methodLabel = '${j['method_label'] ?? '—'}',
      company = _str(j['company']),
      issuedAt = _date(j['issued_at']),
      paidAt = _date(j['paid_at']);

  final int id;
  final String number, description, amountText, status, statusTag, methodLabel;
  final String? company;
  final DateTime? issuedAt, paidAt;
}

class UsageMetric {
  UsageMetric.fromJson(Map<String, dynamic> j)
    : label = '${j['label'] ?? ''}',
      used = _num(j['used']),
      limit = _numOrNull(j['limit']),
      unit = '${j['unit'] ?? ''}',
      unlimited = j['unlimited'] == true,
      percent = _numOrNull(j['percent']),
      exceeded = j['exceeded'] == true;

  final String label;
  final double used;
  final double? limit;
  final String unit;
  final bool unlimited;
  final double? percent;
  final bool exceeded;
}

class PlatformSubscription {
  PlatformSubscription.fromJson(Map<String, dynamic> j)
    : status = '${j['status'] ?? ''}',
      billingCycle = _str(j['billing_cycle']),
      startsAt = _date(j['starts_at']);

  final String status;
  final String? billingCycle;
  final DateTime? startsAt;
}

class PlatformAdmin {
  PlatformAdmin.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      initials = _str(j['initials']),
      email = '${j['email'] ?? ''}',
      status = '${j['status'] ?? ''}';

  final int id;
  final String name;
  final String? initials;
  final String email, status;
}

/// GET /platform/companies/{id}: the company plus usage, subscription,
/// recent invoices and its administrators.
class CompanyDetail {
  CompanyDetail.fromJson(Map<String, dynamic> j)
    : company = PlatformCompany.fromJson(_map(j['data'])),
      usage = {
        for (final e in _map(j['usage']).entries)
          if (e.value is Map) e.key: _map(e.value),
      },
      subscription = j['subscription'] is Map ? PlatformSubscription.fromJson(_map(j['subscription'])) : null,
      invoices = [for (final e in _list(j['invoices'])) PlatformInvoice.fromJson(e)],
      admins = [for (final e in _list(j['admins'])) PlatformAdmin.fromJson(e)];

  final PlatformCompany company;
  final Map<String, Map<String, dynamic>> usage;
  final PlatformSubscription? subscription;
  final List<PlatformInvoice> invoices;
  final List<PlatformAdmin> admins;

  UsageMetric? metric(String key) => usage[key] == null ? null : UsageMetric.fromJson(usage[key]!);

  /// The plan's approval-level limit (null = unlimited).
  int? get approvalLevelsLimit => _intOrNull(usage['approval_levels']?['limit']);
}

class OverviewStage {
  OverviewStage.fromJson(Map<String, dynamic> j)
    : position = _int(j['position']),
      name = '${j['name'] ?? ''}',
      role = _str(j['role']),
      count = _int(j['count']),
      value = _num(j['value']);

  final int position;
  final String name;
  final String? role;
  final int count;
  final double value;
}

class RecentPayment {
  RecentPayment.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      number = '${j['number'] ?? ''}',
      payee = '${j['payee'] ?? ''}',
      purpose = '${j['purpose'] ?? ''}',
      amount = _num(j['amount']),
      currency = _str(j['currency']),
      kind = '${j['kind'] ?? ''}',
      paymentMethod = _str(j['payment_method']),
      paymentReference = _str(j['payment_reference']),
      paymentDate = _date(j['payment_date']),
      paidAt = _date(j['paid_at']),
      paidBy = _str(j['paid_by']),
      department = _str(j['department']);

  final int id;
  final String number, payee, purpose;
  final double amount;
  final String? currency;
  final String kind;
  final String? paymentMethod, paymentReference;
  final DateTime? paymentDate, paidAt;
  final String? paidBy, department;
}

class MonthlyPoint {
  MonthlyPoint.fromJson(Map<String, dynamic> j)
    : month = '${j['month'] ?? ''}',
      count = _int(j['count']),
      value = _num(j['value']);

  final String month;
  final int count;
  final double value;

  DateTime? get date => DateTime.tryParse('$month-01');
}

/// GET /platform/companies/{id}/overview.
class CompanyOverview {
  CompanyOverview.fromJson(Map<String, dynamic> j)
    : vouchers = {for (final e in _map(j['vouchers']).entries) e.key: _int(e.value)},
      values = {for (final e in _map(j['values']).entries) e.key: _num(e.value)},
      stages = [for (final e in _list(j['stages'])) OverviewStage.fromJson(e)],
      paidCount = _int(_map(j['payments'])['paid_count']),
      paidValue = _num(_map(j['payments'])['paid_value']),
      pendingCount = _int(_map(j['payments'])['pending_count']),
      pendingValue = _num(_map(j['payments'])['pending_value']),
      recentPayments = [for (final e in _list(_map(j['payments'])['recent'])) RecentPayment.fromJson(e)],
      peopleTotal = _int(_map(j['people'])['total']),
      peopleActive = _int(_map(j['people'])['active']),
      byRole = {for (final e in _map(_map(j['people'])['by_role']).entries) e.key: _int(e.value)},
      departments = _int(_map(j['people'])['departments']),
      monthly = [for (final e in _list(j['monthly'])) MonthlyPoint.fromJson(e)],
      currency = '${j['currency'] ?? 'TZS'}';

  final Map<String, int> vouchers;
  final Map<String, double> values;
  final List<OverviewStage> stages;
  final int paidCount;
  final double paidValue;
  final int pendingCount;
  final double pendingValue;
  final List<RecentPayment> recentPayments;
  final int peopleTotal, peopleActive;
  final Map<String, int> byRole;
  final int departments;
  final List<MonthlyPoint> monthly;
  final String currency;

  int v(String key) => vouchers[key] ?? 0;
  double value(String key) => values[key] ?? 0;
}

class PersonRef {
  PersonRef.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      email = _str(j['email']),
      role = _str(j['role']);

  final int id;
  final String name;
  final String? email, role;
}

class DepartmentRow {
  DepartmentRow.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      code = _str(j['code']),
      costCentre = _str(j['cost_centre']),
      isActive = j['is_active'] != false,
      hod = j['hod'] is Map ? PersonRef.fromJson(_map(j['hod'])) : null,
      manager = j['manager'] is Map ? PersonRef.fromJson(_map(j['manager'])) : null,
      usersCount = _int(j['users_count']),
      vouchersCount = _int(j['vouchers_count']),
      approvedValue = _num(j['approved_value']);

  final int id;
  final String name;
  final String? code, costCentre;
  final bool isActive;
  final PersonRef? hod, manager;
  final int usersCount, vouchersCount;
  final double approvedValue;
}

class WorkflowStepInfo {
  WorkflowStepInfo.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      position = _int(j['position']),
      name = '${j['name'] ?? ''}',
      label = _str(j['label']),
      role = '${j['role'] ?? ''}',
      roleLabel = '${j['role_label'] ?? j['role'] ?? ''}',
      assignedUserName = _str(_map(j['assigned_user'])['name']),
      canSign = j['can_sign'] == true,
      canApprove = j['can_approve'] == true,
      canReject = j['can_reject'] == true,
      canRequestChanges = j['can_request_changes'] == true,
      canPay = j['can_pay'] == true,
      requiresSignature = j['requires_signature'] == true,
      minAmount = _numOrNull(j['min_amount']),
      maxAmount = _numOrNull(j['max_amount']),
      isRequestStep = j['is_request_step'] == true;

  final int id, position;
  final String name;
  final String? label;
  final String role, roleLabel;
  final String? assignedUserName;
  final bool canSign, canApprove, canReject, canRequestChanges, canPay, requiresSignature;
  final double? minAmount, maxAmount;
  final bool isRequestStep;
}

class WorkflowInfo {
  WorkflowInfo.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['label'] ?? j['name'] ?? ''}',
      description = _str(j['description']),
      voucherTypeName = _str(_map(j['voucher_type'])['name']),
      isDefault = j['is_default'] == true,
      isActive = j['is_active'] != false,
      version = _int(j['version']),
      vouchersCount = _int(j['vouchers_count']),
      steps = [for (final e in _list(j['steps'])) WorkflowStepInfo.fromJson(e)];

  final int id;
  final String name;
  final String? description, voucherTypeName;
  final bool isDefault, isActive;
  final int version, vouchersCount;
  final List<WorkflowStepInfo> steps;
}

class RoutingStep {
  RoutingStep.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      position = _int(j['position']),
      name = '${j['name'] ?? ''}',
      isRequestStep = j['is_request_step'] == true;

  final int id, position;
  final String name;
  final bool isRequestStep;
}

class RoutingCell {
  RoutingCell.fromJson(Map<String, dynamic> j)
    : stepId = _int(j['step_id']),
      people = [for (final e in _list(j['people'])) PersonRef.fromJson(e)],
      gap = _str(j['gap']);

  final int stepId;
  final List<PersonRef> people;
  final String? gap;
}

class RoutingDepartment {
  RoutingDepartment.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name'] ?? ''}',
      cells = [for (final e in _list(j['cells'])) RoutingCell.fromJson(e)],
      gaps = _int(j['gaps']);

  final int id;
  final String name;
  final List<RoutingCell> cells;
  final int gaps;
}

/// GET /platform/companies/{id}/workflows.
class CompanyWorkflows {
  CompanyWorkflows.fromJson(Map<String, dynamic> j)
    : workflows = [for (final e in _list(j['workflows'])) WorkflowInfo.fromJson(e)],
      routingSteps = [for (final e in _list(_map(j['routing'])['steps'])) RoutingStep.fromJson(e)],
      routingDepartments = [for (final e in _list(_map(j['routing'])['departments'])) RoutingDepartment.fromJson(e)],
      hasRouting = j['routing'] is Map,
      gaps = _int(_map(j['routing'])['gaps']);

  final List<WorkflowInfo> workflows;
  final List<RoutingStep> routingSteps;
  final List<RoutingDepartment> routingDepartments;
  final bool hasRouting;
  final int gaps;
}

/// One voucher row of GET /platform/companies/{id}/vouchers.
class PlatformVoucherRow {
  PlatformVoucherRow.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      number = '${j['number'] ?? ''}',
      status = '${j['status'] ?? ''}',
      statusTag = '${j['status_tag'] ?? 'tag-neutral'}',
      statusLabelEn = '${j['status_label_en'] ?? j['status_label'] ?? ''}',
      statusLabelSw = '${j['status_label_sw'] ?? j['status_label'] ?? ''}',
      typeLabel = _str(_map(j['voucher_type'])['label']) ?? '${j['kind'] ?? ''}',
      purpose = '${j['purpose'] ?? ''}',
      payee = '${j['payee'] ?? ''}',
      requester = _str(_map(j['requester'])['name']),
      department = _str(_map(j['department'])['name']),
      amount = _num(j['amount']),
      currency = '${j['currency'] ?? 'TZS'}',
      amountText = _str(j['amount_text']),
      currentStepName = _str(_map(j['current_step'])['name']),
      currentStepPosition = _intOrNull(j['current_step_position']),
      createdAt = _date(j['created_at'] ?? j['voucher_date']),
      updatedAt = _date(j['updated_at']);

  final int id;
  final String number, status, statusTag, statusLabelEn, statusLabelSw, typeLabel, purpose, payee;
  final String? requester, department;
  final double amount;
  final String currency;
  final String? amountText;
  final String? currentStepName;
  final int? currentStepPosition;
  final DateTime? createdAt, updatedAt;
}

/// One audit-log entry (GET /audit-logs?company_id=…).
class AuditEntry {
  AuditEntry.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      action = '${j['action'] ?? ''}',
      description = '${j['description'] ?? ''}',
      changeSummary = _str(j['change_summary']),
      entityType = _str(j['entity_type']),
      entityId = _intOrNull(j['entity_id']),
      actorName = '${_map(j['actor'])['name'] ?? ''}',
      actorRole = _str(_map(j['actor'])['role']),
      createdAt = _date(j['created_at']);

  final int id;
  final String action, description;
  final String? changeSummary, entityType;
  final int? entityId;
  final String actorName;
  final String? actorRole;
  final DateTime? createdAt;
}
