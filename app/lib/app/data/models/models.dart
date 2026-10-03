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
      colorTheme = '${json['color_theme'] ?? 'blue'}',
      status = '${json['status']}',
      isUsable = json['is_usable'] == true,
      isExpired = json['is_expired'] == true,
      daysRemaining = _as<int>(json['days_remaining']),
      trialEndsAt = _toDate(json['trial_ends_at']),
      currentPeriodEnd = _toDate(json['current_period_end']),
      plan = _plan(json['plan']);

  final int id;
  final String name, email, currency, locale, primaryColor, status;

  /// The interface palette: blue, emerald, violet or rose.
  final String colorTheme;
  final String? phone, address, logoUrl, logoMarkUrl, legalName, website, tin;
  final String? bankName, bankAccountName, bankAccountNumber, bankBranch;
  final String? voucherFooterText;
  final bool isUsable, isExpired;
  final int? daysRemaining;
  final DateTime? trialEndsAt, currentPeriodEnd;
  final Plan? plan;

  /// Registered but not yet approved by the platform: nothing but the
  /// account, billing and the waiting screen is open to it.
  bool get isPending => status == 'pending';
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
      theme = '${json['theme'] ?? 'dark'}',
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
      download = json?['download'] == true,
      attach = json?['attach'] == true || json?['edit'] == true;

  final bool
  edit,
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
  download,
  /// Documents may be added — also after approval and payment, for receipts.
  attach;

  bool get hasWorkflowAction =>
      sign || submitSigned || approve || reject || requestChanges || pay;
}

class TimelineEntry {
  TimelineEntry.fromJson(Map<String, dynamic> json)
    : position = _toInt(json['position']),
      name = '${json['name']}',
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

  final int position;
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
      isImage = json['is_image'] == true,
      mimeType = _as<String>(json['mime_type']),
      uploadedBy = _as<String>(json['uploaded_by']),
      createdAt = _toDate(json['created_at']),
      documentType = _as<String>(json['document_type']),
      voucherPaymentId = _as<num>(json['voucher_payment_id'])?.toInt();

  final int id;
  final String name, size;
  final bool isImage;
  final String? mimeType, uploadedBy;
  final DateTime? createdAt;

  bool get isPdf =>
      mimeType == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

  /// `payment_acknowledgement` for a signed cash receipt; null otherwise.
  final String? documentType;

  /// The payment a signed acknowledgement belongs to.
  final int? voucherPaymentId;

  bool get isAcknowledgement => documentType == 'payment_acknowledgement';
}

/// One release of money against a voucher. A voucher approved for 10m may be
/// paid 9m now and the 1m balance later — each is its own record.
class VoucherPayment {
  VoucherPayment.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      sequence = _toInt(json['sequence']),
      reference = '${json['reference'] ?? ''}',
      amount = _toDouble(json['amount']),
      amountText = '${json['amount_text'] ?? ''}',
      balanceAfter = _toDouble(json['balance_after']),
      balanceAfterText = '${json['balance_after_text'] ?? ''}',
      paymentMethod = _as<String>(json['payment_method']),
      paymentReference = _as<String>(json['payment_reference']),
      chequeNumber = _as<String>(json['cheque_number']),
      receivedBy = _as<String>(json['received_by']),
      receiverIdNumber = _as<String>(json['receiver_id_number']),
      paymentDate = _toDate(json['payment_date']),
      paidAt = _toDate(json['paid_at']),
      // Sent as a name; tolerate an object too.
      paidBy = json['paid_by'] is Map
          ? _nested(json['paid_by'], 'name')
          : _as<String>(json['paid_by']),
      paidById = _as<num>(json['paid_by_id'])?.toInt(),
      note = _as<String>(json['note']),
      acknowledgedAt = _toDate(json['acknowledged_at']),
      acknowledgementUrl = _as<String>(json['acknowledgement_url']),
      acknowledgementAttachmentIds =
          (json['acknowledgement_attachment_ids'] as List? ?? [])
              .map(_toInt)
              .toList();

  final int id, sequence;
  final String reference, amountText, balanceAfterText;
  final double amount, balanceAfter;
  final String? paymentMethod,
      paymentReference,
      chequeNumber,
      receivedBy,
      receiverIdNumber,
      paidBy,
      note,
      acknowledgementUrl;
  final int? paidById;
  final DateTime? paymentDate, paidAt, acknowledgedAt;
  final List<int> acknowledgementAttachmentIds;

  /// A signed copy has been filed against this payment.
  bool get isAcknowledged =>
      acknowledgedAt != null || acknowledgementAttachmentIds.isNotEmpty;
}

class VoucherComment {
  VoucherComment.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      body = '${json['body']}',
      authorName = _nested(json['user'], 'name') ?? '—',
      authorInitials = _nested(json['user'], 'initials') ?? '',
      authorDepartment = _nested(json['user'], 'department'),
      authorRole = _nested(json['user'], 'role_label'),
      createdAt = _toDate(json['created_at']);

  final int id;
  final String body, authorName, authorInitials;
  final String? authorDepartment, authorRole;
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
      amountPaid = _toDouble(json['amount_paid']),
      amountPaidText = _as<String>(json['amount_paid_text']),
      balance = json['balance'] == null ? null : _toDouble(json['balance']),
      balanceText = _as<String>(json['balance_text']),
      isPartiallyPaid =
          json['is_partially_paid'] == true ||
          json['status_key'] == 'partially_paid',
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
      paymentDate = _toDate(json['payment_date']),
      rejectedAt = _toDate(json['rejected_at']),
      updatedAt = _toDate(json['updated_at']),
      decidedBy = _as<String>(json['decided_by']),
      workflowId = _as<num>(json['workflow_id'])?.toInt(),
      currentStepPosition = _as<num>(json['current_step_position'])?.toInt(),
      currentStepRole = _nested(json['current_step'], 'role'),
      currentStepCanSign = _stepCan(json['current_step'], 'sign'),
      requesterJobTitle = _nested(json['requester'], 'job_title'),
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
          .toList(),
      payments = (json['payments'] is List ? json['payments'] as List : [])
          .whereType<Map>()
          .map((e) => VoucherPayment.fromJson(Map<String, dynamic>.from(e)))
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
      notesToApprover,
      decidedBy,
      currentStepRole,
      requesterJobTitle;
  final int? workflowId, currentStepPosition;
  final bool currentStepCanSign;
  final double amount;
  final bool currentStepCanApprove, isEditable, isTerminal;

  /// Released so far, and what remains. Older payloads carry neither: a paid
  /// voucher then owes nothing, anything else owes the whole amount.
  final double amountPaid;
  final double? balance;
  final String? amountPaidText, balanceText;

  /// Some money released, the rest still owed.
  final bool isPartiallyPaid;

  /// What is still owed on this voucher.
  double get outstanding =>
      balance ?? (status == 'paid' ? 0 : amount - amountPaid);

  /// The chip tag: a part-paid voucher reads as a warning, whatever the
  /// server's tag, because money is still owed on it.
  String get displayTag => isPartiallyPaid ? 'tag-warn' : statusTag;

  bool get isCash => kind == 'cash';
  final DateTime? voucherDate, submittedAt, approvedAt, paidAt, createdAt;
  final DateTime? paymentDate, rejectedAt, updatedAt;
  final VoucherActions actions;
  final List<TimelineEntry> timeline;
  final List<Attachment> attachments;
  final List<VoucherComment> comments;
  final List<VoucherPayment> payments;
}

class AppNotificationItem {
  AppNotificationItem.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      type = '${json['type'] ?? ''}',
      icon = '${json['icon'] ?? 'ph-bell'}',
      title = '${json['title']}',
      body = _as<String>(json['body']),
      entityType = _as<String>(json['entity_type']),
      entityId = _as<int>(json['entity_id']),
      actionUrl = _as<String>(json['action_url']),
      isUnread = json['is_unread'] == true,
      readAt = _toDate(json['read_at']),
      createdAt = _toDate(json['created_at']);

  final int id;
  final String type, title;

  /// The web's Phosphor class name, e.g. `ph-seal-check`.
  final String icon;
  final String? body, entityType, actionUrl;
  final int? entityId;
  final bool isUnread;
  final DateTime? readAt, createdAt;
}

/// String params from a JSON object (`{}` or a list when empty in PHP).
Map<String, String> _params(dynamic value) => value is Map
    ? value.map((k, v) => MapEntry('$k', '$v'))
    : const <String, String>{};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

class DashboardStat {
  DashboardStat.fromJson(Map<String, dynamic> json)
    : key = _as<String>(json['key']),
      params = _params(json['params']),
      label = '${json['label']}',
      value = '${json['value']}',
      sub = '${json['sub'] ?? ''}',
      subKey = _as<String>(json['sub_key']),
      subParams = _params(json['sub_params']),
      icon = _as<String>(json['icon']),
      trend = _as<String>(json['trend']),
      up = json['up'] as bool?;

  /// Stable translation key, e.g. `dash.stat.awaitingApproval`.
  final String? key, subKey;
  final Map<String, String> params, subParams;
  final String label, value, sub;
  final String? icon, trend;
  final bool? up;
}

/// "You have 3 vouchers waiting for your attention." — or the all-clear.
class DashboardBanner {
  DashboardBanner.fromJson(Map<String, dynamic> json)
    : count = _toInt(json['count']),
      key = '${json['key'] ?? ''}',
      params = _params(json['params']),
      title = '${json['title'] ?? ''}',
      bodyKey = _as<String>(json['body_key']),
      body = '${json['body'] ?? ''}',
      actionKey = _as<String>((json['action'] as Map?)?['key']),
      actionLabel = _as<String>((json['action'] as Map?)?['label']),
      actionHref = _as<String>((json['action'] as Map?)?['href']);

  final int count;
  final String key, title, body;
  final String? bodyKey, actionKey, actionLabel, actionHref;
  final Map<String, String> params;
}

/// One workflow event on a voucher the viewer may see.
class DashboardActivity {
  DashboardActivity.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      action = '${json['action'] ?? ''}',
      actionLabel = '${json['action_label'] ?? json['action'] ?? ''}',
      actorId = _as<int>(json['actor_id']),
      actor = '${json['actor'] ?? '—'}',
      voucherId = _toInt(json['voucher_id']),
      voucherNumber = '${json['voucher_number'] ?? '#${json['voucher_id']}'}',
      amountText = _as<String>(json['amount_text']),
      at = _as<String>(json['at']);

  final int id, voucherId;
  final int? actorId;
  final String action, actionLabel, actor, voucherNumber;
  final String? amountText, at;
}

/// A named bar: a department's approved spend, or a stage's open work.
class DashboardBar {
  DashboardBar.fromJson(Map<String, dynamic> json)
    : id = _as<int>(json['id']),
      name = '${json['name'] ?? ''}',
      count = _toInt(json['count']),
      total = _toDouble(json['total']),
      totalText = _as<String>(json['total_text']),
      share = _share(json['share']);

  final int? id;
  final String name;
  final int count;
  final double total;
  final String? totalText;

  /// 0–1, from the API's "42%".
  final double share;

  static double _share(dynamic value) {
    final text = '${value ?? ''}'.replaceAll('%', '').trim();
    final n = double.tryParse(text) ?? 0;
    return (n / 100).clamp(0, 1).toDouble();
  }
}

/// One month of voucher value, for the seven-month column chart.
class DashboardVolume {
  DashboardVolume.fromJson(Map<String, dynamic> json)
    : period = '${json['period'] ?? ''}',
      label = '${json['label'] ?? ''}',
      count = _toInt(json['count']),
      total = _toDouble(json['total']),
      isCurrent = json['is_current'] == true;

  final String period, label;
  final int count;
  final double total;
  final bool isCurrent;
}

/// A voucher this approver signed recently (the HOD panel).
class DashboardSigned {
  DashboardSigned.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      number = '${json['number'] ?? ''}',
      payee = '${json['payee'] ?? ''}',
      amountText = '${json['amount_text'] ?? ''}',
      status = '${json['status'] ?? ''}';

  final int id;
  final String number, payee, amountText, status;
}

/// A count and a sum of payments (the cashier's totals).
class DashboardMoneyTotal {
  DashboardMoneyTotal.fromJson(Map<String, dynamic>? json)
    : count = _toInt(json?['count']),
      total = _toDouble(json?['total']),
      totalText = '${json?['total_text'] ?? ''}';

  final int count;
  final double total;
  final String totalText;
}

/// The company's default approval route, step by step (admin panel).
class DashboardWorkflow {
  DashboardWorkflow.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name'] ?? ''}',
      nameSw = _as<String>(json['name_sw']),
      steps = _maps(json['steps']).map(DashboardWorkflowStep.fromJson).toList();

  final int id;
  final String name;
  final String? nameSw;
  final List<DashboardWorkflowStep> steps;
}

class DashboardWorkflowStep {
  DashboardWorkflowStep.fromJson(Map<String, dynamic> json)
    : position = _toInt(json['position']),
      name = '${json['name'] ?? ''}',
      nameSw = _as<String>(json['name_sw']),
      role = '${json['role'] ?? ''}',
      action = '${json['action'] ?? ''}';

  final int position;
  final String name, role;
  final String? nameSw;

  /// request | sign | approve | pay | review
  final String action;
}

class DashboardSubscription {
  DashboardSubscription.fromJson(Map<String, dynamic> json)
    : plan = _as<String>(json['plan']),
      status = '${json['status'] ?? ''}',
      trialEndsAt = _toDate(json['trial_ends_at']),
      renewsAt = _toDate(json['renews_at']),
      daysRemaining = json['days_remaining'] == null
          ? null
          : _toInt(json['days_remaining']);

  final String? plan;
  final String status;
  final DateTime? trialEndsAt, renewsAt;
  final int? daysRemaining;
}

/// A company the platform should talk to (trial ending, payment overdue).
class DashboardAttention {
  DashboardAttention.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name'] ?? ''}',
      status = '${json['status'] ?? ''}',
      plan = _as<String>(json['plan']),
      usersCount = _toInt(json['users_count']),
      note = '${json['note'] ?? ''}';

  final int id, usersCount;
  final String name, status, note;
  final String? plan;
}

/// A company in the platform's "Recent companies" list.
class DashboardCompany {
  DashboardCompany.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      name = '${json['name'] ?? ''}',
      plan = _as<String>(json['plan']),
      status = '${json['status'] ?? ''}',
      usersCount = _toInt(json['users_count']),
      vouchersCount = _toInt(json['vouchers_count']);

  final int id, usersCount, vouchersCount;
  final String name, status;
  final String? plan;
}

/// A subscription invoice in the platform's "Recent payments".
class DashboardInvoice {
  DashboardInvoice.fromJson(Map<String, dynamic> json)
    : id = _toInt(json['id']),
      number = '${json['number'] ?? ''}',
      company = _as<String>(json['company']),
      total = _toDouble(json['total']),
      currency = '${json['currency'] ?? 'TZS'}',
      status = '${json['status'] ?? ''}',
      createdAt = _toDate(json['created_at']);

  final int id;
  final String number, currency, status;
  final String? company;
  final double total;
  final DateTime? createdAt;
}

/// A queued voucher's place in its route, which the list model does not
/// carry: the workflow it follows and the step it sits at.
class DashboardQueueRoute {
  DashboardQueueRoute.fromJson(Map<String, dynamic> json)
    : workflowId = _as<int>(json['workflow_id']),
      currentStepPosition = _as<int>(json['current_step_position']);

  final int? workflowId, currentStepPosition;
}

/// The whole `/dashboard` payload. Which blocks are present is decided by the
/// backend per role; every optional block is null when it was not sent.
class DashboardData {
  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};
    final queueRaw = _maps(json['queue'] ?? data['queue']);

    Map<String, dynamic>? map(String key) =>
        data[key] is Map ? Map<String, dynamic>.from(data[key] as Map) : null;
    List<T>? list<T>(String key, T Function(Map<String, dynamic>) f) =>
        data[key] is List ? _maps(data[key]).map(f).toList() : null;

    final totals = map('payment_totals');
    final overview = map('overview');

    return DashboardData._(
      greeting: '${json['greeting'] ?? ''}',
      role: '${json['role'] ?? ''}',
      view: '${data['view'] ?? ''}',
      headline: '${data['headline'] ?? ''}',
      sub: '${data['sub'] ?? ''}',
      banner: map('banner') == null
          ? null
          : DashboardBanner.fromJson(map('banner')!),
      stats: _maps(data['stats']).map(DashboardStat.fromJson).toList(),
      queue: queueRaw.map(Voucher.fromJson).toList(),
      queueRoutes: queueRaw.map(DashboardQueueRoute.fromJson).toList(),
      queueTotalText: _as<String>(
        json['queue_total_text'] ?? data['queue_total_text'],
      ),
      activity: list('recent_activity', DashboardActivity.fromJson),
      activityKey: _as<String>(data['recent_activity_key']),
      activityLabel: '${data['recent_activity_label'] ?? 'Recent activity'}',
      recentlySigned: list('recently_signed', DashboardSigned.fromJson),
      byDepartment: list('by_department', DashboardBar.fromJson),
      byStage: list('by_stage', DashboardBar.fromJson),
      volume: list('volume', DashboardVolume.fromJson),
      paymentTotals: totals == null
          ? null
          : (
              paid: DashboardMoneyTotal.fromJson(_mapOf(totals['paid'])),
              bank: DashboardMoneyTotal.fromJson(_mapOf(totals['bank'])),
              cash: DashboardMoneyTotal.fromJson(_mapOf(totals['cash'])),
            ),
      overview: overview == null
          ? null
          : (
              activeUsers: _toInt(overview['active_users']),
              departments: _toInt(overview['departments']),
            ),
      hasWorkflow: data.containsKey('workflow'),
      workflow: map('workflow') == null
          ? null
          : DashboardWorkflow.fromJson(map('workflow')!),
      subscription: map('subscription') == null
          ? null
          : DashboardSubscription.fromJson(map('subscription')!),
      attention: list('attention', DashboardAttention.fromJson),
      recentCompanies: list('recent_companies', DashboardCompany.fromJson),
      recentPayments: list('recent_payments', DashboardInvoice.fromJson),
    );
  }

  DashboardData._({
    required this.greeting,
    required this.role,
    required this.view,
    required this.headline,
    required this.sub,
    required this.banner,
    required this.stats,
    required this.queue,
    required this.queueRoutes,
    required this.queueTotalText,
    required this.activity,
    required this.activityKey,
    required this.activityLabel,
    required this.recentlySigned,
    required this.byDepartment,
    required this.byStage,
    required this.volume,
    required this.paymentTotals,
    required this.overview,
    required this.hasWorkflow,
    required this.workflow,
    required this.subscription,
    required this.attention,
    required this.recentCompanies,
    required this.recentPayments,
  });

  final String greeting, role, view, headline, sub, activityLabel;
  final String? activityKey, queueTotalText;
  final DashboardBanner? banner;
  final List<DashboardStat> stats;

  /// The work that is this user's to do right now.
  final List<Voucher> queue;

  /// Parallel to [queue]: each voucher's workflow and current step.
  final List<DashboardQueueRoute> queueRoutes;

  final List<DashboardActivity>? activity;
  final List<DashboardSigned>? recentlySigned;
  final List<DashboardBar>? byDepartment, byStage;
  final List<DashboardVolume>? volume;
  final ({
    DashboardMoneyTotal paid,
    DashboardMoneyTotal bank,
    DashboardMoneyTotal cash,
  })?
  paymentTotals;
  final ({int activeUsers, int departments})? overview;

  /// The admin payload names `workflow` even when no default route is active.
  final bool hasWorkflow;
  final DashboardWorkflow? workflow;
  final DashboardSubscription? subscription;
  final List<DashboardAttention>? attention;
  final List<DashboardCompany>? recentCompanies;
  final List<DashboardInvoice>? recentPayments;
}

Map<String, dynamic>? _mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
