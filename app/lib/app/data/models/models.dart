/// Plain data models mirroring the API resources.
library;

T? _as<T>(dynamic value) => value is T ? value : null;

double _toDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

int _toInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

DateTime? _toDate(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// Reads a field out of a nested object that the API may omit entirely.
String? _nested(dynamic parent, String key) {
  if (parent is! Map) return null;
  final value = parent[key];
  return value == null ? null : '$value';
}

bool _cap(dynamic caps, String key) => caps is Map && caps[key] == true;

bool _stepCan(dynamic step, String capability) {
  if (step is! Map) return false;
  final caps = step['capabilities'];
  return caps is Map && caps[capability] == true;
}

Plan? _plan(dynamic value) =>
    value is Map<String, dynamic> ? Plan.fromJson(value) : null;

class Plan {
  Plan.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      code = '${json['code']}',
      name = '${json['name']}',
      label = '${json['label'] ?? json['name']}',
      blurb = _as<String>(json['blurb']),
      price = _toDouble(json['price']),
      currency = '${json['currency'] ?? 'TZS'}',
      maxUsers = _as<int>(json['max_users']),
      maxVouchers = _as<int>(json['max_vouchers_per_month']),
      trialDays = _toInt(json['trial_days']),
      features = (json['features'] as List? ?? []).map((e) => '$e').toList();

  final int id;
  final String code, name, label, currency;
  final String? blurb;
  final double price;
  final int? maxUsers, maxVouchers;
  final int trialDays;
  final List<String> features;
}

class Company {
  Company.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name']}',
      email = '${json['email'] ?? ''}',
      phone = _as<String>(json['phone']),
      address = _as<String>(json['address']),
      currency = '${json['currency'] ?? 'TZS'}',
      locale = '${json['locale'] ?? 'en'}',
      logoUrl = _as<String>(json['logo_url']),
      logoMarkUrl = _as<String>(json['logo_mark_url']),
      legalName = _as<String>(json['legal_name']),
      website = _as<String>(json['website']),
      tin = _as<String>(json['tin']),
      bankName = _as<String>(json['bank_name']),
      bankAccountName = _as<String>(json['bank_account_name']),
      bankAccountNumber = _as<String>(json['bank_account_number']),
      bankBranch = _as<String>(json['bank_branch']),
      voucherFooterText = _as<String>(json['voucher_footer_text']),
      primaryColor = '${json['primary_color'] ?? '#0088b0'}',
      status = '${json['status']}',
      isUsable = json['is_usable'] == true,
      isExpired = json['is_expired'] == true,
      daysRemaining = _as<int>(json['days_remaining']),
      trialEndsAt = _toDate(json['trial_ends_at']),
      currentPeriodEnd = _toDate(json['current_period_end']),
      plan = _plan(json['plan']);

  final int id;
  final String name, email, currency, locale, primaryColor, status;
  final String? phone, address, logoUrl, logoMarkUrl, legalName, website, tin;
  final String? bankName, bankAccountName, bankAccountNumber, bankBranch;
  final String? voucherFooterText;
  final bool isUsable, isExpired;
  final int? daysRemaining;
  final DateTime? trialEndsAt, currentPeriodEnd;
  final Plan? plan;
}

class AppUser {
  AppUser.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      companyId = _as<int>(json['company_id']),
      name = '${json['name']}',
      initials = '${json['initials'] ?? ''}',
      email = '${json['email']}',
      phone = _as<String>(json['phone']),
      role = '${json['role']}',
      roleLabel = '${json['role_label'] ?? json['role']}',
      jobTitle = _as<String>(json['job_title']),
      employeeCode = _as<String>(json['employee_code']),
      status = '${json['status'] ?? 'active'}',
      locale = '${json['locale'] ?? 'en'}',
      theme = '${json['theme'] ?? 'light'}',
      departmentId = _as<int>(json['department_id']),
      departmentName = _nested(json['department'], 'name'),
      avatarUrl = _as<String>(json['avatar_url']),
      hasSignature = json['has_signature'] == true;

  final int id;
  final int? companyId, departmentId;
  final String name, initials, email, role, roleLabel, status, locale, theme;
  final String? phone, jobTitle, employeeCode, departmentName, avatarUrl;
  final bool hasSignature;

  bool get isEmployee => role == 'employee';
  bool get isApprover =>
      const ['hod', 'ceo', 'finance', 'director'].contains(role);

  /// Releases funds; never makes an approval decision.
  bool get isCashier => role == 'cashier';
  bool get canCreateVouchers => !isCashier && !isSuperAdmin;
  bool get isAdmin => role == 'company_admin' || role == 'super_admin';
  bool get isSuperAdmin => role == 'super_admin';
}

class Department {
  Department.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name']}';

  final int id;
  final String name;
}

class VoucherType {
  VoucherType.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name']}',
      label = '${json['label'] ?? json['name']}',
      nextNumberPreview = '${json['next_number_preview'] ?? ''}';

  final int id;
  final String name, label, nextNumberPreview;
}

class VoucherActions {
  VoucherActions.fromJson(Map<String, dynamic>? json)
    : edit = json?['edit'] == true,
      delete = json?['delete'] == true,
      submit = json?['submit'] == true,
      sign = json?['sign'] == true,
      submitSigned = json?['submit_signed'] == true,
      approve = json?['approve'] == true,
      reject = json?['reject'] == true,
      requestChanges = json?['request_changes'] == true,
      cancel = json?['cancel'] == true,
      pay = json?['pay'] == true,
      print = json?['print'] == true,
      download = json?['download'] == true;

  final bool edit,
      delete,
      submit,
      sign,
      submitSigned,
      approve,
      reject,
      requestChanges,
      cancel,
      pay,
      print,
      download;

  bool get hasWorkflowAction =>
      sign || submitSigned || approve || reject || requestChanges || pay;
}

class TimelineEntry {
  TimelineEntry.fromJson(Map<String, dynamic> json)
    : name = '${json['name']}',
      nameSw = _as<String>(json['name_sw']),
      sub = '${json['sub']}',
      subSw = '${json['sub_sw'] ?? json['sub']}',
      person = '${json['person']}',
      personTitle = _as<String>(json['person_title']),
      act = '${json['act']}',
      actSw = '${json['act_sw'] ?? json['act']}',
      when = _toDate(json['when']),
      comment = _as<String>(json['comment']),
      signature = _as<String>(json['signature']),
      capabilityText = '${json['capability_text'] ?? ''}',
      capabilitySign = _cap(json['capabilities'], 'sign'),
      capabilityApprove = _cap(json['capabilities'], 'approve'),
      capabilityPay = _cap(json['capabilities'], 'pay'),
      state = '${json['state']}';

  final String name, sub, subSw, person, act, actSw, capabilityText, state;
  final String? nameSw, comment, signature, personTitle;
  final bool capabilitySign, capabilityApprove, capabilityPay;
  final DateTime? when;

  String label(String locale) => locale == 'sw' ? (nameSw ?? name) : name;
  String action(String locale) => locale == 'sw' ? actSw : act;
  String step(String locale) => locale == 'sw' ? subSw : sub;
}

class Attachment {
  Attachment.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name']}',
      size = '${json['size']}',
      isImage = json['is_image'] == true;

  final int id;
  final String name, size;
  final bool isImage;
}

class VoucherComment {
  VoucherComment.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      body = '${json['body']}',
      authorName = _nested(json['user'], 'name') ?? '—',
      authorInitials = _nested(json['user'], 'initials') ?? '',
      createdAt = _toDate(json['created_at']);

  final int id;
  final String body, authorName, authorInitials;
  final DateTime? createdAt;
}

class Voucher {
  Voucher.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      number = '${json['number']}',
      kind = json['kind'] == 'cash' ? 'cash' : 'bank',
      status = '${json['status']}',
      statusKey = '${json['status_key']}',
      statusLabel = '${json['status_label']}',
      statusTag = '${json['status_tag']}',
      payee = '${json['payee']}',
      purpose = '${json['purpose']}',
      description = _as<String>(json['description']),
      amount = _toDouble(json['amount']),
      currency = '${json['currency'] ?? 'TZS'}',
      amountText = '${json['amount_text']}',
      amountInWords = _as<String>(json['amount_in_words']),
      paymentMethod = _as<String>(json['payment_method']),
      accountRef = _as<String>(json['account_ref']),
      category = _as<String>(json['category']),
      costCentre = _as<String>(json['cost_centre']),
      verificationCode = _as<String>(json['verification_code']),
      voucherDate = _toDate(json['voucher_date']),
      submittedAt = _toDate(json['submitted_at']),
      approvedAt = _toDate(json['approved_at']),
      paidAt = _toDate(json['paid_at']),
      paymentReference = _as<String>(json['payment_reference']),
      // The API sends the payer as an object, not a name.
      paidBy = _nested(json['paid_by'], 'name'),
      payeeBank = _as<String>(json['payee_bank']),
      payeeAccountName = _as<String>(json['payee_account_name']),
      payeeAccountNumber = _as<String>(json['payee_account_number']),
      payeeBankBranch = _as<String>(json['payee_bank_branch']),
      chequeNumber = _as<String>(json['cheque_number']),
      cashFloat = _as<String>(json['cash_float']),
      receivedBy = _as<String>(json['received_by']),
      notesToApprover = _as<String>(json['notes_to_approver']),
      createdAt = _toDate(json['created_at']),
      voucherTypeId = _toInt(json['voucher_type_id']),
      voucherTypeLabel = _nested(json['voucher_type'], 'label'),
      departmentId = _as<int>(json['department_id']),
      departmentName = _nested(json['department'], 'name'),
      requesterName = _nested(json['requester'], 'name'),
      requesterId = _toInt(json['requester_id']),
      currentStepName = _nested(json['current_step'], 'name'),
      currentStepCanApprove = _stepCan(json['current_step'], 'approve'),
      isEditable = json['is_editable'] == true,
      isTerminal = json['is_terminal'] == true,
      attachmentsCount = _as<int>(json['attachments_count']) ?? 0,
      actions = VoucherActions.fromJson(
        _as<Map<String, dynamic>>(json['actions']),
      ),
      timeline = (json['timeline'] as List? ?? [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      attachments = (json['attachments'] as List? ?? [])
          .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      comments = (json['comments'] as List? ?? [])
          .map((e) => VoucherComment.fromJson(e as Map<String, dynamic>))
          .toList();

  final int id, voucherTypeId, requesterId, attachmentsCount;
  final int? departmentId;
  final String number, kind, status, statusKey, statusLabel, statusTag;
  final String payee, purpose, currency, amountText;
  final String? description,
      amountInWords,
      paymentMethod,
      accountRef,
      category,
      costCentre,
      verificationCode,
      voucherTypeLabel,
      departmentName,
      requesterName,
      currentStepName,
      paymentReference,
      paidBy,
      payeeBank,
      payeeAccountName,
      payeeAccountNumber,
      payeeBankBranch,
      chequeNumber,
      cashFloat,
      receivedBy,
      notesToApprover;
  final double amount;
  final bool currentStepCanApprove, isEditable, isTerminal;

  bool get isCash => kind == 'cash';
  final DateTime? voucherDate, submittedAt, approvedAt, paidAt, createdAt;
  final VoucherActions actions;
  final List<TimelineEntry> timeline;
  final List<Attachment> attachments;
  final List<VoucherComment> comments;
}

class AppNotificationItem {
  AppNotificationItem.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      title = '${json['title']}',
      body = _as<String>(json['body']),
      entityType = _as<String>(json['entity_type']),
      entityId = _as<int>(json['entity_id']),
      isUnread = json['is_unread'] == true,
      createdAt = _toDate(json['created_at']);

  final int id;
  final String title;
  final String? body, entityType;
  final int? entityId;
  final bool isUnread;
  final DateTime? createdAt;
}

class DashboardStat {
  DashboardStat.fromJson(Map<String, dynamic> json)
    : label = '${json['label']}',
      value = '${json['value']}',
      sub = '${json['sub'] ?? ''}',
      icon = _as<String>(json['icon']),
      trend = _as<String>(json['trend']),
      up = json['up'] as bool?;

  final String label, value, sub;
  final String? icon, trend;
  final bool? up;
}

class DashboardData {
  DashboardData.fromJson(Map<String, dynamic> json)
    : greeting = '${json['greeting'] ?? ''}',
      role = '${json['role'] ?? ''}',
      headline = '${(json['data'] as Map)['headline']}',
      sub = '${(json['data'] as Map)['sub'] ?? ''}',
      stats = ((json['data'] as Map)['stats'] as List? ?? [])
          .map((e) => DashboardStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      queueTotalText = '${json['queue_total_text'] ?? ''}',
      // The action queue is the payload's own, not a slice of the data block:
      // a dashboard is what is on you, not what has happened.
      queue = ((json['queue'] ?? (json['data'] as Map)['queue']) as List? ?? [])
          .map((e) => Voucher.fromJson(e as Map<String, dynamic>))
          .toList(),
      recent = ((json['data'] as Map)['recent'] as List? ?? [])
          .map((e) => Voucher.fromJson(e as Map<String, dynamic>))
          .toList();

  final String greeting, role, headline, sub, queueTotalText;
  final List<DashboardStat> stats;
  final List<Voucher> queue, recent;
}
