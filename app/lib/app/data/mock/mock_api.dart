import 'dart:math';

import '../services/api_service.dart';
import 'mock_seed.dart';

/// The in-app stand-in for the Laravel API.
///
/// It answers the same paths, with the same verbs and the same JSON shapes, so
/// [ApiService] can route to it in Phase 1 and to HTTP in Phase 2 without any
/// screen, controller or model changing.
class MockApi {
  MockApi() {
    _seed();
  }

  // ── the dataset ──
  final _users = <MockUser>[];
  final _departments = <MockDepartment>[];
  final _types = <MockVoucherType>[];
  final _vouchers = <MockVoucher>[];
  final _approvals = <MockApproval>[];
  final _notifications = <MockNotification>[];
  final List<MockStep> _steps = defaultSteps();

  int _nextVoucherId = 1,
      _nextApprovalId = 1,
      _nextNotificationId = 1,
      _nextCommentId = 1;

  MockUser? _current;

  static const _company = {
    'id': 1,
    'name': 'Acme Tanzania Ltd',
    'slug': 'acme-tanzania',
    'legal_name': 'Acme Tanzania Limited',
    'email': 'accounts@acme-demo.test',
    'phone': '+255 712 000 101',
    'address': 'Plot 44, Mikocheni · Dar es Salaam',
    'currency': 'TZS',
    'locale': 'en',
    'logo_url': null,
    'primary_color': '#2f7bf6',
    'status': 'active',
    'is_usable': true,
    'is_expired': false,
    'days_remaining': 24,
    'trial_ends_at': null,
    'voucher_footer_text':
        'This voucher is computer generated and valid without a wet stamp.',
    'plan': {
      'id': 2,
      'code': 'business',
      'name': 'Business',
      'label': 'Business',
      'blurb': 'Departments, branding and reporting for growing companies.',
      'price': 249000,
      'currency': 'TZS',
      'max_users': 50,
      'max_vouchers_per_month': null,
      'trial_days': 14,
      'features': [
        '50 users',
        'Unlimited vouchers',
        '3 approval levels',
        'Custom branding',
        'Reports & exports',
      ],
    },
  };

  /* ══════════════════════════════════════════════════════════ dispatch ══ */

  /// Answers one request. [path] never carries a query string.
  Future<dynamic> handle(
    String method,
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) async {
    // A little latency, so loading states are exercised as they will be.
    await Future<void>.delayed(
      Duration(milliseconds: 120 + Random().nextInt(180)),
    );

    final seg = path.replaceFirst(RegExp(r'^/+'), '').split('/');

    if (method == 'POST' && path == '/auth/login') return _login(body);

    if (_current == null) {
      throw ApiException(401, 'Your session has ended. Sign in again.');
    }

    switch (path) {
      case '/auth/me':
        return {'user': _userJson(_current!), 'company': _company};
      case '/auth/logout':
        _current = null;
        return {'message': 'Signed out.'};
      case '/auth/change-password':
        if ('${body['current_password']}' != 'Password123!') {
          throw ApiException(422, 'That is not your current password.', {
            'current_password': ['That is not your current password.'],
          });
        }
        return {'message': 'Password updated.'};
      case '/profile':
        for (final key in ['locale', 'theme', 'name', 'job_title']) {
          final value = body[key];
          if (value == null) continue;
          if (key == 'locale') _current!.locale = '$value';
          if (key == 'theme') _current!.theme = '$value';
          if (key == 'job_title') _current!.jobTitle = '$value';
        }
        return {'data': _userJson(_current!)};
      case '/profile/signature':
        if (method == 'GET') return {'signature': _current!.signature};
        if (method == 'DELETE') {
          _current!.signature = null;
          return {'message': 'Signature removed.'};
        }
        _current!.signature = '${body['signature']}';
        return {'message': 'Signature saved.'};
      case '/dashboard':
        return _dashboard();
      case '/departments':
        return {
          'data': _departments
              .where((d) => d.companyId == _current!.companyId)
              .map(
                (d) => {
                  'id': d.id,
                  'name': d.name,
                  'cost_centre': d.costCentre,
                },
              )
              .toList(),
        };
      case '/voucher-types':
        return {
          'data': _types
              .where((t) => t.companyId == _current!.companyId)
              .map(
                (t) => {
                  'id': t.id,
                  'name': t.name,
                  'label': _current!.locale == 'sw' ? t.nameSw : t.name,
                  'next_number_preview': _previewNumber(t),
                },
              )
              .toList(),
        };
      case '/vouchers/pending':
        return {'data': _pending().map((v) => _voucherJson(v)).toList()};
      case '/notifications':
        final rows = _notifications
            .where((n) => n.userId == _current!.id)
            .toList();
        return {
          'data': rows.map(_notificationJson).toList(),
          'meta': {'unread_count': rows.where((n) => n.readAt == null).length},
        };
      case '/notifications/unread-count':
        return {
          'unread_count': _notifications
              .where((n) => n.userId == _current!.id && n.readAt == null)
              .length,
        };
      case '/notifications/read-all':
        var count = 0;
        for (final n in _notifications) {
          if (n.userId == _current!.id && n.readAt == null) {
            n.readAt = DateTime.now().toIso8601String();
            count++;
          }
        }
        return {'count': count};
    }

    if (seg.first == 'notifications' && seg.length == 3 && seg[2] == 'read') {
      final id = int.tryParse(seg[1]);
      for (final n in _notifications) {
        if (n.id == id) n.readAt = DateTime.now().toIso8601String();
      }
      return {
        'data': {'id': id},
      };
    }

    if (path == '/vouchers' && method == 'GET') return _index(query);
    if (path == '/vouchers' && method == 'POST') return _create(body);

    if (seg.first == 'vouchers' && seg.length >= 2) {
      final id = int.tryParse(seg[1]);
      if (id == null) throw ApiException(404, 'Voucher not found.');
      final voucher = _find(id);

      if (seg.length == 2 && method == 'GET') {
        return {'data': _voucherJson(voucher, detailed: true)};
      }
      if (seg.length == 2 && method == 'PUT') return _update(voucher, body);
      if (seg.length == 2 && method == 'DELETE') {
        _vouchers.removeWhere((v) => v.id == id);
        return {'message': 'Draft deleted.'};
      }
      if (seg.length == 3 && method == 'POST') {
        return _act(voucher, seg[2], body);
      }
    }

    throw ApiException(404, 'No mock route for $method $path');
  }

  /* ═══════════════════════════════════════════════════════════ actions ══ */

  Map<String, dynamic> _login(Map<String, dynamic> body) {
    final email = '${body['email'] ?? ''}'.trim().toLowerCase();
    final user = _users.where((u) => u.email == email).firstOrNull;
    if (user == null || '${body['password']}' != 'Password123!') {
      throw ApiException(422, 'These credentials do not match our records.', {
        'email': ['These credentials do not match our records.'],
      });
    }
    _current = user;
    return {
      'token': 'mock-${user.id}-${DateTime.now().millisecondsSinceEpoch}',
      'user': _userJson(user),
      'company': _company,
    };
  }

  Map<String, dynamic> _index(Map<String, dynamic> query) {
    var rows = _visible().toList();

    final scope = '${query['scope'] ?? 'all'}';
    if (scope == 'mine') {
      rows = rows.where((v) => v.requesterId == _current!.id).toList();
    } else if (scope == 'pending') {
      rows = _pending();
    }

    final status = query['status'];
    if (status != null && '$status'.isNotEmpty && status != 'all') {
      rows = switch ('$status') {
        'pending' => rows.where((v) => v.status == 'in_review').toList(),
        'drafts' => rows.where((v) => v.status == 'draft').toList(),
        final s => rows.where((v) => v.status == s).toList(),
      };
    }
    if (query['kind'] != null && '${query['kind']}'.isNotEmpty) {
      rows = rows.where((v) => v.kind == '${query['kind']}').toList();
    }

    final q = '${query['q'] ?? ''}'.trim().toLowerCase();
    if (q.length > 1) {
      rows = rows.where((v) {
        final requester = _user(v.requesterId)?.name ?? '';
        return '${v.number}${v.purpose}${v.payee}$requester'
            .toLowerCase()
            .contains(q);
      }).toList();
    }

    rows.sort((a, b) => b.voucherDate.compareTo(a.voucherDate));

    final perPage = int.tryParse('${query['per_page'] ?? 20}') ?? 20;
    final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
    final start = (page - 1) * perPage;
    final slice = rows.skip(start).take(perPage).toList();

    return {
      'data': slice.map((v) => _voucherJson(v)).toList(),
      'meta': {
        'current_page': page,
        'last_page': (rows.length / perPage).ceil().clamp(1, 9999),
        'per_page': perPage,
        'total': rows.length,
        'total_amount': rows.fold<double>(0, (sum, v) => sum + v.amount),
        'currency': 'TZS',
      },
    };
  }

  Map<String, dynamic> _create(Map<String, dynamic> body) {
    final type = _types.firstWhere(
      (t) => t.id == int.tryParse('${body['voucher_type_id']}'),
      orElse: () => _types.first,
    );
    final id = _nextVoucherId++;
    final voucher = MockVoucher(
      id: id,
      companyId: _current!.companyId ?? 1,
      number: _takeNumber(type),
      kind: body['kind'] == 'cash' ? 'cash' : 'bank',
      voucherTypeId: type.id,
      departmentId:
          int.tryParse('${body['department_id']}') ?? _current!.departmentId,
      requesterId: _current!.id,
      payee: '${body['payee'] ?? ''}',
      purpose: '${body['purpose'] ?? ''}',
      description: body['description'] as String?,
      amount: double.tryParse('${body['amount'] ?? 0}') ?? 0,
      paymentMethod: body['payment_method'] as String?,
      category: body['category'] as String?,
      accountRef: body['account_ref'] as String?,
      voucherDate:
          '${body['voucher_date'] ?? DateTime.now().toIso8601String().substring(0, 10)}',
      status: 'draft',
      currentStepPosition: null,
      createdAt: DateTime.now().toIso8601String(),
      notesToApprover: body['notes_to_approver'] as String?,
    );
    _vouchers.insert(0, voucher);
    _log(voucher, 'created', null);

    if (body['submit'] == true) _act(voucher, 'submit', const {});
    return {'data': _voucherJson(voucher, detailed: true)};
  }

  Map<String, dynamic> _update(MockVoucher v, Map<String, dynamic> body) {
    if (!_actions(v)['edit']!) {
      throw ApiException(403, 'This voucher can no longer be edited.');
    }
    v.payee = '${body['payee'] ?? v.payee}';
    v.purpose = '${body['purpose'] ?? v.purpose}';
    v.description = body['description'] as String? ?? v.description;
    v.amount = double.tryParse('${body['amount'] ?? v.amount}') ?? v.amount;
    v.paymentMethod = body['payment_method'] as String? ?? v.paymentMethod;
    v.accountRef = body['account_ref'] as String? ?? v.accountRef;
    v.category = body['category'] as String? ?? v.category;
    if (body['kind'] != null) v.kind = '${body['kind']}';
    if (body['department_id'] != null) {
      v.departmentId = int.tryParse('${body['department_id']}');
    }
    return {'data': _voucherJson(v, detailed: true)};
  }

  Map<String, dynamic> _act(
    MockVoucher v,
    String action,
    Map<String, dynamic> body,
  ) {
    final actions = _actions(v);
    final step = _stepAt(v.currentStepPosition);
    final comment = body['comment'] as String?;
    final now = DateTime.now().toIso8601String();

    switch (action) {
      case 'submit':
        if (!actions['submit']!) {
          throw ApiException(422, 'This voucher has already been submitted.');
        }
        final first = _applicable(v).where((s) => s.position != 1).firstOrNull;
        _log(
          v,
          v.status == 'changes_requested' ? 'resubmitted' : 'submitted',
          _applicable(v).first,
          comment: comment,
        );
        v.submittedAt ??= now;
        if (first == null) {
          v.status = 'paid';
          v.currentStepPosition = null;
        } else {
          v.status = 'in_review';
          v.currentStepPosition = first.position;
          v.stepSignedAt = null;
          _notifyAssignees(v, first);
        }

      case 'sign':
        if (!actions['sign']!) {
          throw ApiException(422, 'That action is not available at this step.');
        }
        final signature = body['use_saved_signature'] == true
            ? _current!.signature
            : (body['signature'] as String? ?? _current!.signature);
        if (signature == null) {
          throw ApiException(422, 'A signature is required.');
        }
        if (body['save_signature'] == true && body['signature'] != null) {
          _current!.signature = '${body['signature']}';
        }
        _log(v, 'signed', step, comment: comment, signature: signature);
        v.stepSignedAt = now;
        _notify(
          v.requesterId,
          title: '${v.number} signed by ${_current!.name}',
          titleSw: '${v.number} imesainiwa na ${_current!.name}',
          icon: 'signature',
          body: '${step?.name ?? 'This step'} complete.',
          voucherId: v.id,
        );

      case 'submit-signed':
        if (!actions['submit_signed']!) {
          throw ApiException(422, 'Sign the voucher before submitting it on.');
        }
        _log(v, 'forwarded', step, comment: comment);
        _advance(v, step!.position);

      case 'approve':
        if (!actions['approve']!) {
          throw ApiException(422, 'This step signs only; it cannot approve.');
        }
        if (step!.canSign && v.stepSignedAt == null) {
          final signature = body['signature'] as String? ?? _current!.signature;
          if (signature != null) {
            _log(v, 'signed', step, signature: signature);
            v.stepSignedAt = now;
          }
        }
        _log(v, 'approved', step, comment: comment);
        v.approvedAt = now;
        _advance(v, step.position);
        _notify(
          v.requesterId,
          title: '${v.number} approved',
          titleSw: '${v.number} imeidhinishwa',
          icon: 'seal',
          body: 'Cleared for payment — the cashier will release the funds.',
          voucherId: v.id,
        );

      case 'reject':
        if (!actions['reject']!) {
          throw ApiException(422, 'This step may not reject.');
        }
        if (comment == null || comment.trim().length < 3) {
          throw ApiException(422, 'A reason is required.', {
            'comment': ['A reason is required.'],
          });
        }
        _log(v, 'rejected', step, comment: comment);
        v.status = 'rejected';
        v.rejectedAt = now;
        v.currentStepPosition = null;
        _notify(
          v.requesterId,
          title: '${v.number} was rejected',
          titleSw: '${v.number} imekataliwa',
          icon: 'x',
          body: '${_current!.name}: $comment',
          voucherId: v.id,
        );

      case 'request-changes':
        if (!actions['request_changes']!) {
          throw ApiException(422, 'This step may not request changes.');
        }
        if (comment == null || comment.trim().length < 3) {
          throw ApiException(422, 'Say what needs to change.', {
            'comment': ['Say what needs to change.'],
          });
        }
        _log(v, 'changes_requested', step, comment: comment);
        v.status = 'changes_requested';
        v.currentStepPosition = null;
        v.stepSignedAt = null;
        _notify(
          v.requesterId,
          title: '${v.number} needs changes',
          titleSw: '${v.number} inahitaji mabadiliko',
          icon: 'undo',
          body: '${_current!.name}: $comment',
          voucherId: v.id,
        );

      case 'pay':
        if (!actions['pay']!) {
          throw ApiException(422, 'This voucher is not cleared for payment.');
        }
        final reference = '${body['reference'] ?? ''}'.trim();
        if (reference.isEmpty) {
          throw ApiException(422, 'A payment reference is required.', {
            'reference': ['A payment reference is required.'],
          });
        }
        _log(
          v,
          'paid',
          step,
          comment:
              comment ??
              'Funds released and reference recorded against the voucher.',
        );
        v.status = 'paid';
        v.paidAt = now;
        v.paymentReference = reference;
        v.paidBy = _current!.name;
        v.currentStepPosition = null;
        if (body['method'] != null) v.paymentMethod = '${body['method']}';
        _notify(
          v.requesterId,
          title: '${v.number} has been paid',
          titleSw: '${v.number} imelipwa',
          icon: 'check',
          body: '${_current!.name} released ${_money(v.amount)} · $reference.',
          voucherId: v.id,
        );

      case 'cancel':
        _log(v, 'cancelled', step, comment: comment);
        v.status = 'cancelled';
        v.currentStepPosition = null;

      case 'comments':
        final text = '${body['body'] ?? ''}'.trim();
        if (text.isEmpty) throw ApiException(422, 'Write something first.');
        v.comments.add(MockComment(_nextCommentId++, _current!.id, text, now));

      default:
        throw ApiException(404, 'Unknown action "$action".');
    }

    return {'data': _voucherJson(v, detailed: true)};
  }

  void _advance(MockVoucher v, int fromPosition) {
    final next = _applicable(
      v,
    ).where((s) => s.position > fromPosition).firstOrNull;

    if (next == null) {
      v.status = 'paid';
      v.paidAt ??= DateTime.now().toIso8601String();
      v.currentStepPosition = null;
      v.stepSignedAt = null;
      return;
    }

    v.currentStepPosition = next.position;
    v.stepSignedAt = null;
    // A payment step is only reached once the voucher has been approved.
    v.status = next.canPay && !next.canApprove ? 'approved' : 'in_review';
    _notifyAssignees(v, next);
  }

  /* ═════════════════════════════════════════════════════════ workflow ══ */

  List<MockStep> _applicable(MockVoucher v) => _steps
      .where(
        (s) =>
            (s.minAmount == null || v.amount >= s.minAmount!) &&
            (s.maxAmount == null || v.amount <= s.maxAmount!),
      )
      .toList();

  MockStep? _stepAt(int? position) => position == null
      ? null
      : _steps.where((s) => s.position == position).firstOrNull;

  List<MockUser> _assignees(MockVoucher v, MockStep step) {
    if (step.assignedUserId != null) {
      final u = _user(step.assignedUserId!);
      return u == null ? [] : [u];
    }
    final dept = _departments.where((d) => d.id == v.departmentId).firstOrNull;

    if (step.role == 'employee') {
      final u = _user(v.requesterId);
      return u == null ? [] : [u];
    }
    if (step.role == 'hod' && dept?.hodUserId != null) {
      final u = _user(dept!.hodUserId!);
      if (u != null) return [u];
    }
    if (step.role == 'ceo' && dept?.managerUserId != null) {
      final u = _user(dept!.managerUserId!);
      if (u != null) return [u];
    }
    return _users
        .where((u) => u.companyId == v.companyId && u.role == step.role)
        .toList();
  }

  bool _canActOn(MockVoucher v, MockStep? step) {
    if (step == null || _current == null) return false;
    if (_current!.role == 'company_admin') return true;
    return _assignees(v, step).any((u) => u.id == _current!.id);
  }

  Map<String, bool> _actions(MockVoucher v) {
    final me = _current!;
    final mine = v.requesterId == me.id;
    final step = _stepAt(v.currentStepPosition);
    final open = v.status == 'in_review' || v.status == 'approved';
    final canAct = open && _canActOn(v, step);
    final signedHere = v.stepSignedAt != null;

    final a = {
      'edit': false,
      'delete': false,
      'submit': false,
      'sign': false,
      'submit_signed': false,
      'approve': false,
      'reject': false,
      'request_changes': false,
      'cancel': false,
      'pay': false,
      'print': true,
      'download': true,
    };

    if (mine && (v.status == 'draft' || v.status == 'changes_requested')) {
      a['edit'] = true;
      a['submit'] = true;
      a['delete'] = v.status == 'draft';
    }
    if (mine && v.status == 'in_review') a['cancel'] = true;

    if (canAct && step != null) {
      if (step.canSign && !signedHere) a['sign'] = true;
      if (step.canSign && signedHere) a['submit_signed'] = true;
      if (step.canApprove) a['approve'] = v.status == 'in_review';
      if (step.canReject) a['reject'] = v.status == 'in_review';
      if (step.canRequestChanges) {
        a['request_changes'] = v.status == 'in_review';
      }
      if (step.canPay && v.status == 'approved') a['pay'] = true;
      a['print'] = step.canPrint;
      a['download'] = step.canPrint;
    }
    return a;
  }

  /// Vouchers this caller is permitted to see. An employee sees only their own.
  Iterable<MockVoucher> _visible() {
    final me = _current!;
    final mine = _vouchers.where((v) => v.companyId == me.companyId);

    if (me.role == 'employee') {
      return mine.where((v) => v.requesterId == me.id);
    }
    if (me.role == 'cashier') {
      return mine.where((v) => v.status == 'approved' || v.status == 'paid');
    }
    if (me.role == 'company_admin') return mine;

    // An approver sees their own vouchers, their departments' vouchers, and
    // anything that has reached or passed a step they act on.
    final scoped = _departments
        .where((d) => d.hodUserId == me.id || d.managerUserId == me.id)
        .map((d) => d.id)
        .toSet();

    return mine.where(
      (v) =>
          v.requesterId == me.id ||
          scoped.contains(v.departmentId) ||
          _approvals.any((e) => e.voucherId == v.id && e.actorId == me.id) ||
          _canActOn(v, _stepAt(v.currentStepPosition)),
    );
  }

  List<MockVoucher> _pending() => _visible()
      .where(
        (v) =>
            (v.status == 'in_review' || v.status == 'approved') &&
            _canActOn(v, _stepAt(v.currentStepPosition)),
      )
      .toList();

  /* ═══════════════════════════════════════════════════ presentation ══ */

  MockUser? _user(int id) => _users.where((u) => u.id == id).firstOrNull;

  static String _money(double amount, [String currency = 'TZS']) {
    final whole = amount.round().toString();
    final grouped = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '$currency $grouped';
  }

  static String _compact(double n) {
    if (n >= 1e9) return 'TZS ${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return 'TZS ${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return 'TZS ${(n / 1e3).round()}K';
    return _money(n);
  }

  static String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
      .join();

  static const _roleLabels = {
    'employee': 'Employee',
    'hod': 'Head of Department',
    'ceo': 'CEO',
    'cashier': 'Cashier',
    'finance': 'Finance',
    'director': 'Director',
    'company_admin': 'Company Administrator',
    'super_admin': 'Platform Super Admin',
  };

  Map<String, dynamic> _userJson(MockUser u) => {
    'id': u.id,
    'company_id': u.companyId,
    'name': u.name,
    'initials': _initials(u.name),
    'email': u.email,
    'phone': null,
    'role': u.role,
    'role_label': _roleLabels[u.role] ?? u.role,
    'job_title': u.jobTitle,
    'employee_code': u.employeeCode,
    'status': u.status,
    'locale': u.locale,
    'theme': u.theme,
    'department_id': u.departmentId,
    'department': u.departmentId == null
        ? null
        : {
            'id': u.departmentId,
            'name':
                _departments
                    .where((d) => d.id == u.departmentId)
                    .firstOrNull
                    ?.name ??
                '',
          },
    'avatar_url': null,
    'has_signature': u.signature != null,
  };

  ({String key, String label, String labelSw, String tag}) _status(
    MockVoucher v,
  ) {
    switch (v.status) {
      case 'draft':
        return (
          key: 'draft',
          label: 'Draft',
          labelSw: 'Rasimu',
          tag: 'tag-neutral',
        );
      case 'rejected':
        return (
          key: 'rejected',
          label: 'Rejected',
          labelSw: 'Imekataliwa',
          tag: 'tag-accent-2',
        );
      case 'changes_requested':
        return (
          key: 'changes',
          label: 'Changes requested',
          labelSw: 'Mabadiliko yameombwa',
          tag: 'tag-accent-2',
        );
      case 'cancelled':
        return (
          key: 'cancelled',
          label: 'Cancelled',
          labelSw: 'Imeghairiwa',
          tag: 'tag-neutral',
        );
      case 'approved':
        return (
          key: 'awaiting_payment',
          label: 'Approved — awaiting payment',
          labelSw: 'Imeidhinishwa — inasubiri malipo',
          tag: 'tag-info',
        );
      case 'paid':
        return (
          key: 'paid',
          label: 'Paid & completed',
          labelSw: 'Imelipwa na kukamilika',
          tag: 'tag-accent',
        );
      default:
        final step = _stepAt(v.currentStepPosition);
        if (step == null) {
          return (
            key: 'in_review',
            label: 'In review',
            labelSw: 'Inapitiwa',
            tag: 'tag-outline',
          );
        }
        if (step.canSign && v.stepSignedAt != null) {
          return (
            key: 'signed',
            label: 'Signed — ready to submit',
            labelSw: 'Imesainiwa — tayari kutumwa',
            tag: 'tag-outline',
          );
        }
        if (step.canPay) {
          return (
            key: 'awaiting_payment',
            label: 'Awaiting payment',
            labelSw: 'Inasubiri malipo',
            tag: 'tag-info',
          );
        }
        if (step.canApprove) {
          return (
            key: 'pending_approval',
            label: 'Awaiting CEO approval',
            labelSw: 'Inasubiri idhini ya mkurugenzi',
            tag: 'tag-outline',
          );
        }
        return (
          key: 'pending_signature',
          label: 'Awaiting HOD signature',
          labelSw: 'Inasubiri sahihi ya mkuu wa idara',
          tag: 'tag-outline',
        );
    }
  }

  String _capabilityText(MockStep s) {
    final on = <String>[
      if (s.canSign) 'Sign',
      if (s.canApprove) 'Approve',
      if (s.canReject) 'Reject',
      if (s.canRequestChanges) 'Request changes',
      if (s.canPay) 'Record payment',
      if (s.canPrint) 'Print / PDF',
    ];
    return on.isEmpty ? 'View only' : on.join(' · ');
  }

  Map<String, dynamic> _voucherJson(MockVoucher v, {bool detailed = false}) {
    final status = _status(v);
    final step = _stepAt(v.currentStepPosition);
    final requester = _user(v.requesterId);
    final dept = _departments.where((d) => d.id == v.departmentId).firstOrNull;
    final type = _types.where((t) => t.id == v.voucherTypeId).firstOrNull;
    final sw = _current?.locale == 'sw';

    return {
      'id': v.id,
      'number': v.number,
      'kind': v.kind,
      'status': v.status,
      'status_key': status.key,
      'status_label': sw ? status.labelSw : status.label,
      'status_tag': status.tag,
      'payee': v.payee,
      'purpose': v.purpose,
      'description': v.description,
      'amount': v.amount,
      'currency': v.currency,
      'amount_text': _money(v.amount, v.currency),
      'amount_in_words': _words(v.amount),
      'payment_method': v.paymentMethod,
      'account_ref': v.accountRef,
      'category': v.category,
      'cost_centre': dept?.costCentre,
      'voucher_date': v.voucherDate,
      'verification_code': v.verificationCode,
      'voucher_type_id': v.voucherTypeId,
      'voucher_type': type == null
          ? null
          : {
              'id': type.id,
              'name': type.name,
              'label': sw ? type.nameSw : type.name,
            },
      'department_id': v.departmentId,
      'department': dept == null ? null : {'id': dept.id, 'name': dept.name},
      'requester_id': v.requesterId,
      'requester': requester == null
          ? null
          : {
              'id': requester.id,
              'name': requester.name,
              'initials': _initials(requester.name),
              'job_title': requester.jobTitle,
            },
      'current_step_position': v.currentStepPosition,
      'current_step': step == null
          ? null
          : {
              'id': step.position,
              'position': step.position,
              'name': step.name,
              'role': step.role,
              'capabilities': step.capabilities,
            },
      'is_signed_at_current_step': v.stepSignedAt != null,
      'is_editable': _actions(v)['edit'],
      'is_terminal': const ['paid', 'rejected', 'cancelled'].contains(v.status),
      'submitted_at': v.submittedAt,
      'approved_at': v.approvedAt,
      'rejected_at': v.rejectedAt,
      'paid_at': v.paidAt,
      'payment_reference': v.paymentReference,
      'paid_by': v.paidBy,
      'created_at': v.createdAt,
      'attachments_count': v.attachments.length,
      'comments_count': v.comments.length,
      'actions': _actions(v),
      if (detailed) 'timeline': _timeline(v),
      if (detailed)
        'attachments': [
          for (var i = 0; i < v.attachments.length; i++)
            {
              'id': i + 1,
              'name': v.attachments[i],
              'size': '${180 + i * 46} KB',
              'is_image': v.attachments[i].endsWith('.jpg'),
            },
        ],
      if (detailed)
        'comments': v.comments.map((c) {
          final author = _user(c.userId);
          return {
            'id': c.id,
            'body': c.body,
            'created_at': c.createdAt,
            'user': {
              'id': c.userId,
              'name': author?.name ?? '—',
              'initials': _initials(author?.name ?? '—'),
              'role_label': _roleLabels[author?.role] ?? '',
            },
          };
        }).toList(),
    };
  }

  List<Map<String, dynamic>> _timeline(MockVoucher v) {
    final steps = _applicable(v);
    final trail = _approvals.where((a) => a.voucherId == v.id).toList();
    final paid = v.status == 'paid';
    final rejected = v.status == 'rejected';
    final current = v.currentStepPosition;

    final rows = <Map<String, dynamic>>[];

    for (final step in steps) {
      final events = trail
          .where((e) => e.stepPosition == step.position)
          .toList();
      final atThis = !paid && !rejected && current == step.position;
      final done =
          paid ||
          (current != null && step.position < current) ||
          (rejected &&
              events.any(
                (e) => const [
                  'approved',
                  'signed',
                  'forwarded',
                ].contains(e.action),
              ));

      MockApproval? last(String action) =>
          events.where((e) => e.action == action).lastOrNull;

      final rejectEvent = last('rejected');
      final changesEvent = last('changes_requested');
      final payEvent = last('paid');
      final approveEvent = last('approved');
      final signEvent = last('signed');
      final forwardEvent = last('forwarded');

      var act = 'Not started', actSw = 'Haijaanza';
      String? when, comment;

      if (step.position == 1) {
        if (v.status == 'draft') {
          act = 'Draft — not submitted';
          actSw = 'Rasimu — haijatumwa';
        } else {
          act = 'Created & submitted';
          actSw = 'Imetengenezwa na kutumwa';
          when = v.submittedAt;
          comment = v.attachments.isEmpty
              ? null
              : '${v.attachments.length} supporting document(s) attached.';
        }
      } else if (rejectEvent != null) {
        act = 'Rejected';
        actSw = 'Imekataliwa';
        when = rejectEvent.actedAt;
        comment = rejectEvent.comment;
      } else if (changesEvent != null) {
        act = 'Changes requested';
        actSw = 'Mabadiliko yameombwa';
        when = changesEvent.actedAt;
        comment = changesEvent.comment;
      } else if (payEvent != null) {
        act = 'Paid';
        actSw = 'Imelipwa';
        when = payEvent.actedAt;
        comment = payEvent.comment;
      } else if (approveEvent != null) {
        act = 'Approved';
        actSw = 'Imeidhinishwa';
        when = approveEvent.actedAt;
        comment = approveEvent.comment ?? 'Cleared for payment.';
      } else if (signEvent != null && forwardEvent != null) {
        act = 'Reviewed & signed';
        actSw = 'Imepitiwa na kusainiwa';
        when = signEvent.actedAt;
        comment = 'Signature applied and forwarded to the next step.';
      } else if (signEvent != null && atThis) {
        act = 'Signed — not yet submitted onward';
        actSw = 'Imesainiwa — haijatumwa mbele';
        when = signEvent.actedAt;
        comment = 'This step signs only; it makes no approval decision.';
      } else if (atThis) {
        if (step.canPay) {
          act = 'Awaiting payment';
          actSw = 'Inasubiri malipo';
        } else if (step.canApprove) {
          act = 'Awaiting approval';
          actSw = 'Inasubiri idhini';
        } else {
          act = 'Awaiting signature';
          actSw = 'Inasubiri sahihi';
        }
      }

      final bad = rejectEvent != null || changesEvent != null;
      final good = done && !bad;
      final actor = events.isEmpty ? null : _user(events.last.actorId);
      final assignee = _assignees(v, step).firstOrNull;

      rows.add({
        'position': step.position,
        'name': step.name,
        'name_sw': step.nameSw,
        'sub': 'Step ${step.position} · ${_roleLabels[step.role] ?? step.role}',
        'sub_sw':
            'Hatua ${step.position} · ${_roleLabels[step.role] ?? step.role}',
        'person': actor?.name ?? assignee?.name ?? step.assigneeHint,
        'person_title': actor?.jobTitle ?? assignee?.jobTitle ?? '',
        'act': act,
        'act_sw': actSw,
        'when': when,
        'comment': comment,
        'signature': signEvent?.signature,
        'capabilities': step.capabilities,
        'capability_text': _capabilityText(step),
        'state': bad
            ? 'rejected'
            : (good ? 'done' : (atThis ? 'current' : 'pending')),
        'icon': bad ? 'x' : (good ? 'check' : (atThis ? 'hourglass' : 'dash')),
      });
    }

    rows.add({
      'position': null,
      'name': 'Completed',
      'name_sw': 'Imekamilika',
      'sub': 'System',
      'sub_sw': 'Mfumo',
      'person': 'VouchFlow',
      'person_title': '',
      'act': paid
          ? 'Voucher completed'
          : (rejected ? 'Closed — rejected' : 'Not completed'),
      'act_sw': paid
          ? 'Vocha imekamilika'
          : (rejected ? 'Imefungwa — imekataliwa' : 'Haijakamilika'),
      'when': paid ? v.paidAt : (rejected ? v.rejectedAt : null),
      'comment': paid
          ? 'Approval ID ${v.verificationCode} · PDF ready with every captured mark.'
          : null,
      'signature': null,
      'capabilities': const {'print': true, 'download': true},
      'capability_text': 'Print · Download PDF · Share',
      'state': paid ? 'done' : (rejected ? 'rejected' : 'pending'),
      'icon': paid ? 'check' : 'dash',
    });

    return rows;
  }

  Map<String, dynamic> _notificationJson(MockNotification n) => {
    'id': n.id,
    'icon': n.icon,
    'title': _current?.locale == 'sw' ? n.titleSw : n.title,
    'body': _current?.locale == 'sw' ? n.bodySw : n.body,
    'entity_type': n.voucherId == null ? null : 'Voucher',
    'entity_id': n.voucherId,
    'is_unread': n.readAt == null,
    'created_at': n.createdAt,
  };

  /* ═════════════════════════════════════════════════════════ dashboard ══ */

  Map<String, dynamic> _dashboard() {
    final me = _current!;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final visible = _visible().toList();
    final queue = _pending();

    Map<String, dynamic> stat(
      String label,
      String value,
      String sub, [
      String icon = 'chart',
      String? trend,
      bool? up,
    ]) => {
      'label': label,
      'value': value,
      'sub': sub,
      'icon': icon,
      'trend': trend,
      'up': up,
    };

    String plural(int n) => '$n ${n == 1 ? 'voucher' : 'vouchers'}';
    double total(Iterable<MockVoucher> rows) =>
        rows.fold<double>(0, (sum, v) => sum + v.amount);

    if (me.role == 'cashier') {
      final due = visible.where((v) => v.status == 'approved').toList();
      final settled = visible.where((v) => v.status == 'paid').toList();
      final cash = due.where((v) => v.kind == 'cash').toList();
      final bank = due.where((v) => v.kind == 'bank').toList();
      return {
        'role': me.role,
        'greeting': greeting,
        'data': {
          'headline': '${plural(due.length)} awaiting payment',
          'sub': 'Each one is approved and cleared for release.',
          'stats': [
            stat(
              'Due today',
              '${due.length}',
              _compact(total(due)),
              'hourglass',
            ),
            stat(
              'Cash to release',
              _compact(total(cash)),
              '${plural(cash.length)} · cash',
              'money',
            ),
            stat(
              'Bank transfers',
              _compact(total(bank)),
              '${plural(bank.length)} · bank',
              'bank',
            ),
            stat(
              'Paid',
              '${settled.length}',
              _compact(total(settled)),
              'check',
            ),
          ],
          'queue': due.map((v) => _voucherJson(v)).toList(),
          'recent': settled.take(6).map((v) => _voucherJson(v)).toList(),
        },
      };
    }

    if (me.role == 'employee') {
      final inFlight = visible
          .where((v) => v.status == 'in_review' || v.status == 'approved')
          .toList();
      return {
        'role': me.role,
        'greeting': greeting,
        'data': {
          'headline': inFlight.isEmpty
              ? 'Create a voucher'
              : '${plural(inFlight.length)} in the approval workflow',
          'sub': 'You see only your own vouchers.',
          'stats': [
            stat('My vouchers', '${visible.length}', 'all time', 'receipt'),
            stat(
              'In the workflow',
              '${inFlight.length}',
              'with an approver',
              'hourglass',
            ),
            stat(
              'Paid',
              '${visible.where((v) => v.status == 'paid').length}',
              'released',
              'check',
            ),
            stat(
              'Total requested',
              _compact(total(visible)),
              'all time',
              'coins',
            ),
          ],
          'recent': visible.take(8).map((v) => _voucherJson(v)).toList(),
        },
      };
    }

    if (const ['hod', 'ceo', 'finance', 'director'].contains(me.role)) {
      final signOnly = queue.every(
        (v) => !(_stepAt(v.currentStepPosition)?.canApprove ?? false),
      );
      final acted = _approvals
          .where(
            (a) =>
                a.actorId == me.id &&
                const ['signed', 'approved'].contains(a.action),
          )
          .length;
      return {
        'role': me.role,
        'greeting': greeting,
        'data': {
          'headline': queue.isEmpty
              ? 'Nothing awaiting you'
              : '${plural(queue.length)} awaiting your ${signOnly ? 'signature' : 'decision'}',
          'sub': signOnly
              ? 'Your step signs only — the approval decision sits with a later step.'
              : 'Each one has reached your step in the approval workflow.',
          'stats': [
            stat('Awaiting you', '${queue.length}', 'right now', 'hourglass'),
            stat('Actioned', '$acted', 'signed or approved', 'signature'),
            stat(
              'Returned',
              '${_approvals.where((a) => a.actorId == me.id && const ['rejected', 'changes_requested'].contains(a.action)).length}',
              'all time',
              'undo',
            ),
            stat(
              'Department value',
              _compact(total(visible.where((v) => v.status == 'paid'))),
              'paid to date',
              'chart',
            ),
          ],
          'queue': queue.map((v) => _voucherJson(v)).toList(),
          'recent': visible.take(6).map((v) => _voucherJson(v)).toList(),
        },
      };
    }

    // Company administrator.
    final open = visible
        .where((v) => v.status == 'in_review' || v.status == 'approved')
        .toList();
    final settled = visible.where((v) => v.status == 'paid').toList();
    return {
      'role': me.role,
      'greeting': greeting,
      'data': {
        'headline': open.isEmpty
            ? 'Everything is up to date'
            : '${plural(open.length)} in the approval workflow',
        'sub': visible.isEmpty
            ? 'No vouchers yet.'
            : '${(settled.length / visible.length * 100).round()}% of vouchers have been paid.',
        'stats': [
          stat('Total vouchers', '${visible.length}', 'all time', 'receipt'),
          stat('In workflow', '${open.length}', 'awaiting a step', 'hourglass'),
          stat('Paid', '${settled.length}', _compact(total(settled)), 'check'),
          stat(
            'Awaiting payment',
            '${visible.where((v) => v.status == 'approved').length}',
            'with the cashier',
            'wallet',
          ),
        ],
        'queue': queue.map((v) => _voucherJson(v)).toList(),
        'recent': visible.take(8).map((v) => _voucherJson(v)).toList(),
      },
    };
  }

  /* ═══════════════════════════════════════════════════════════ helpers ══ */

  MockVoucher _find(int id) {
    final v = _vouchers.where((x) => x.id == id).firstOrNull;
    if (v == null) throw ApiException(404, 'Voucher not found.');
    if (!_visible().any((x) => x.id == id)) {
      throw ApiException(
        403,
        'This voucher belongs to another part of the business.',
      );
    }
    return v;
  }

  void _log(
    MockVoucher v,
    String action,
    MockStep? step, {
    String? comment,
    String? signature,
  }) {
    _approvals.add(
      MockApproval(
        id: _nextApprovalId++,
        voucherId: v.id,
        stepPosition: step?.position,
        actorId: _current!.id,
        actorName: _current!.name,
        action: action,
        actedAt: DateTime.now().toIso8601String(),
        comment: comment,
        signature: signature,
      ),
    );
  }

  void _notifyAssignees(MockVoucher v, MockStep step) {
    final verb = step.canPay
        ? 'payment'
        : (step.canApprove ? 'approval' : 'signature');
    for (final u in _assignees(v, step)) {
      _notify(
        u.id,
        title: '${v.number} needs your $verb',
        titleSw:
            '${v.number} inahitaji ${step.canPay ? 'malipo' : (step.canApprove ? 'idhini' : 'sahihi')} yako',
        icon: step.canPay ? 'wallet' : (step.canApprove ? 'seal' : 'signature'),
        body:
            '${_user(v.requesterId)?.name ?? ''} · ${_money(v.amount)} — ${v.purpose}',
        voucherId: v.id,
      );
    }
  }

  void _notify(
    int userId, {
    required String title,
    required String titleSw,
    required String icon,
    String? body,
    int? voucherId,
  }) {
    _notifications.insert(
      0,
      MockNotification(
        id: _nextNotificationId++,
        userId: userId,
        icon: icon,
        title: title,
        titleSw: titleSw,
        body: body,
        bodySw: body,
        createdAt: DateTime.now().toIso8601String(),
        voucherId: voucherId,
      ),
    );
  }

  String _previewNumber(MockVoucherType t) =>
      '${t.prefix}-${DateTime.now().year}-${t.nextNumber.toString().padLeft(6, '0')}';

  String _takeNumber(MockVoucherType t) {
    final value = _previewNumber(t);
    t.nextNumber += 1;
    return value;
  }

  static const _units = [
    '',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  static const _tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  static String _under1000(int n) {
    if (n < 20) return _units[n];
    if (n < 100) {
      return _tens[n ~/ 10] + (n % 10 != 0 ? '-${_units[n % 10]}' : '');
    }
    return '${_units[n ~/ 100]} hundred'
        '${n % 100 != 0 ? ' ${_under1000(n % 100)}' : ''}';
  }

  static String _words(double amount) {
    var rest = amount.round().abs();
    if (rest == 0) return 'Zero shillings only';
    final parts = <String>[];
    for (final pair in const [
      [1000000000, 'billion'],
      [1000000, 'million'],
      [1000, 'thousand'],
    ]) {
      final value = pair[0] as int;
      if (rest >= value) {
        parts.add('${_under1000(rest ~/ value)} ${pair[1]}');
        rest %= value;
      }
    }
    if (rest > 0) parts.add(_under1000(rest));
    final text = parts.join(' ');
    return '${text[0].toUpperCase()}${text.substring(1)} shillings only';
  }

  /* ══════════════════════════════════════════════════════════════ seed ══ */

  void _seed() {
    _departments.addAll(const [
      MockDepartment(1, 1, 'Finance', 'CC-FIN', 4, 5),
      MockDepartment(2, 1, 'Procurement', 'CC-PRO', 9, 5),
      MockDepartment(3, 1, 'Operations', 'CC-OPS', 4, 5),
      MockDepartment(4, 1, 'Human Resources', 'CC-HR', 4, 5),
      MockDepartment(5, 1, 'IT', 'CC-IT', 9, 5),
      MockDepartment(6, 1, 'Sales', 'CC-SLS', 9, 5),
    ]);

    _users.addAll([
      MockUser(
        id: 2,
        companyId: 1,
        name: 'Neema William',
        email: 'admin@acme.test',
        role: 'company_admin',
        jobTitle: 'Company Administrator',
        employeeCode: 'AC-0087',
        departmentId: 4,
      ),
      MockUser(
        id: 3,
        companyId: 1,
        name: 'John Mwakyusa',
        email: 'john@acme.test',
        role: 'employee',
        jobTitle: 'Procurement Officer',
        employeeCode: 'AC-0114',
        departmentId: 2,
      ),
      MockUser(
        id: 4,
        companyId: 1,
        name: 'Asha Mushi',
        email: 'asha@acme.test',
        role: 'hod',
        jobTitle: 'Head of Finance',
        employeeCode: 'AC-0032',
        departmentId: 1,
        signature: sampleSignature,
      ),
      MockUser(
        id: 5,
        companyId: 1,
        name: 'Daniel Joseph',
        email: 'daniel@acme.test',
        role: 'ceo',
        jobTitle: 'Chief Executive Officer',
        employeeCode: 'AC-0008',
        departmentId: 3,
        signature: sampleSignature,
      ),
      MockUser(
        id: 6,
        companyId: 1,
        name: 'Fatuma Kalinga',
        email: 'fatuma@acme.test',
        role: 'cashier',
        jobTitle: 'Cashier · Finance',
        employeeCode: 'AC-0056',
        departmentId: 1,
        signature: sampleSignature,
      ),
      MockUser(
        id: 7,
        companyId: 1,
        name: 'Baraka Ndosi',
        email: 'baraka@acme.test',
        role: 'employee',
        jobTitle: 'IT Officer',
        employeeCode: 'AC-0129',
        departmentId: 5,
      ),
      MockUser(
        id: 9,
        companyId: 1,
        name: 'Peter Sanga',
        email: 'peter@acme.test',
        role: 'hod',
        jobTitle: 'Head of Procurement',
        employeeCode: 'AC-0021',
        departmentId: 2,
        signature: sampleSignature,
      ),
    ]);

    _types.addAll([
      MockVoucherType(101, 1, 'Payment Voucher', 'Vocha ya malipo', 'PV', 1246),
      MockVoucherType(
        102,
        1,
        'Petty Cash Voucher',
        'Vocha ya fedha taslimu',
        'PC',
        319,
      ),
      MockVoucherType(103, 1, 'Expense Voucher', 'Vocha ya matumizi', 'EX', 88),
      MockVoucherType(
        104,
        1,
        'Advance Voucher',
        'Vocha ya malipo ya awali',
        'AD',
        43,
      ),
    ]);

    _addVoucher(
      number: 'PV-2026-001245',
      kind: 'bank',
      typeId: 101,
      dept: 2,
      requester: 3,
      payee: 'Highland Freight Services',
      purpose: 'Freight to Arusha — September consignment',
      description:
          'Road freight, 12 pallets of network hardware, Dar es Salaam depot to the Arusha branch.',
      amount: 4850000,
      method: 'Bank Transfer',
      category: 'Logistics',
      ref: 'INV-88213',
      daysAgo: 2,
      status: 'in_review',
      step: 2,
      attachments: ['invoice-88213.pdf', 'delivery-note.jpg'],
      trail: [
        ('created', 3, null, 2, 8, null, false),
        ('submitted', 3, 1, 2, 8, null, false),
      ],
    );

    _addVoucher(
      number: 'PV-2026-001244',
      kind: 'bank',
      typeId: 101,
      dept: 1,
      requester: 3,
      payee: 'Mikocheni Property Holdings',
      purpose: 'Office rent — Q4 2026',
      description:
          'Quarterly rent for the head office, October to December 2026.',
      amount: 21500000,
      method: 'Bank Transfer',
      category: 'Premises',
      ref: 'RENT-Q4',
      daysAgo: 3,
      status: 'in_review',
      step: 2,
      signedAtStep: true,
      attachments: ['lease-2026.pdf'],
      trail: [
        ('created', 3, null, 3, 7, null, false),
        ('submitted', 3, 1, 3, 8, null, false),
        ('signed', 4, 2, 3, 9, null, true),
      ],
    );

    _addVoucher(
      number: 'PC-2026-000318',
      kind: 'cash',
      typeId: 102,
      dept: 5,
      requester: 7,
      payee: 'Serengeti Computer Supplies',
      purpose: 'Replacement laptop batteries',
      description: 'Six replacement batteries for field laptops.',
      amount: 1450000,
      method: 'Cash',
      category: 'Capital equipment',
      ref: 'Petty cash float 1',
      daysAgo: 4,
      status: 'in_review',
      step: 3,
      trail: [
        ('created', 7, null, 4, 8, null, false),
        ('submitted', 7, 1, 4, 9, null, false),
        ('signed', 9, 2, 4, 11, null, true),
        ('forwarded', 9, 2, 4, 11, null, false),
      ],
    );

    _addVoucher(
      number: 'PV-2026-001240',
      kind: 'bank',
      typeId: 101,
      dept: 1,
      requester: 3,
      payee: 'Riverside Consulting Ltd',
      purpose: 'External audit fieldwork — Q3',
      description:
          'Fieldwork and reporting for the third-quarter statutory audit.',
      amount: 3250000,
      method: 'Bank Transfer',
      category: 'Professional fees',
      ref: 'RC-4410',
      daysAgo: 6,
      status: 'approved',
      step: 4,
      trail: [
        ('created', 3, null, 6, 8, null, false),
        ('submitted', 3, 1, 6, 8, null, false),
        ('signed', 4, 2, 6, 10, null, true),
        ('forwarded', 4, 2, 6, 10, null, false),
        ('approved', 5, 3, 5, 15, null, false),
      ],
    );

    _addVoucher(
      number: 'PC-2026-000317',
      kind: 'cash',
      typeId: 102,
      dept: 3,
      requester: 3,
      payee: 'Kariakoo Stationers',
      purpose: 'Office consumables — September',
      description: 'Paper, toner and filing supplies for the head office.',
      amount: 350000,
      method: 'Cash',
      category: 'Premises',
      ref: 'Petty cash float 1',
      daysAgo: 7,
      status: 'approved',
      step: 4,
      trail: [
        ('created', 3, null, 7, 8, null, false),
        ('submitted', 3, 1, 7, 9, null, false),
        ('signed', 4, 2, 7, 11, null, true),
        ('forwarded', 4, 2, 7, 11, null, false),
        ('approved', 5, 3, 6, 14, null, false),
      ],
    );

    _addVoucher(
      number: 'PV-2026-001238',
      kind: 'bank',
      typeId: 101,
      dept: 5,
      requester: 7,
      payee: 'Uhuru Internet Services',
      purpose: 'Branch connectivity — August',
      description: 'Leased line for the Arusha branch, August 2026.',
      amount: 780000,
      method: 'Bank Transfer',
      category: 'Utilities',
      ref: 'UIS-9921',
      daysAgo: 12,
      status: 'paid',
      step: null,
      paymentRef: 'TRF-2026-4471',
      paidBy: 'Fatuma Kalinga',
      trail: [
        ('created', 7, null, 12, 8, null, false),
        ('submitted', 7, 1, 12, 8, null, false),
        ('signed', 9, 2, 11, 9, null, true),
        ('forwarded', 9, 2, 11, 10, null, false),
        ('approved', 5, 3, 11, 15, null, false),
        ('paid', 6, 4, 10, 10, null, false),
      ],
    );

    _addVoucher(
      number: 'AD-2026-000042',
      kind: 'bank',
      typeId: 104,
      dept: 2,
      requester: 3,
      payee: 'John Mwakyusa',
      purpose: 'Travel advance — Mwanza site visit',
      description:
          'Five nights and local transport for the Mwanza supplier audit.',
      amount: 1250000,
      method: 'Bank Transfer',
      category: 'Transport',
      ref: 'TRV-2026-042',
      daysAgo: 9,
      status: 'rejected',
      step: null,
      trail: [
        ('created', 3, null, 9, 8, null, false),
        ('submitted', 3, 1, 9, 8, null, false),
        ('signed', 9, 2, 9, 10, null, true),
        ('forwarded', 9, 2, 9, 10, null, false),
        (
          'rejected',
          5,
          3,
          8,
          15,
          'Use the branch float for the Mwanza trip — the advance is not needed.',
          false,
        ),
      ],
    );

    _addVoucher(
      number: 'EX-2026-000011',
      kind: 'bank',
      typeId: 103,
      dept: 5,
      requester: 7,
      payee: 'Uhuru Internet Services',
      purpose: 'Branch internet — August arrears',
      description: 'Arrears carried from the July invoice.',
      amount: 620000,
      method: 'Bank Transfer',
      category: 'Utilities',
      ref: 'UIS-9930',
      daysAgo: 5,
      status: 'changes_requested',
      step: null,
      trail: [
        ('created', 7, null, 5, 8, null, false),
        ('submitted', 7, 1, 5, 8, null, false),
        (
          'changes_requested',
          9,
          2,
          5,
          12,
          'Attach the July statement showing the arrears before resubmitting.',
          false,
        ),
      ],
    );

    _addVoucher(
      number: 'PV-2026-001246',
      kind: 'bank',
      typeId: 101,
      dept: 2,
      requester: 3,
      payee: 'Coastal Packaging Ltd',
      purpose: 'Packaging materials — October order',
      description: 'Cartons and pallet wrap for the October despatch cycle.',
      amount: 2750000,
      method: 'Bank Transfer',
      category: 'Logistics',
      ref: '',
      daysAgo: 0,
      status: 'draft',
      step: null,
      trail: [('created', 3, null, 0, 9, null, false)],
    );

    // Enough history for the charts and registers to look lived-in.
    const payees = [
      'Highland Freight Services',
      'Kariakoo Stationers',
      'Uhuru Internet Services',
      'Coastal Packaging Ltd',
    ];
    const purposes = [
      'Monthly courier retainer',
      'Warehouse cleaning contract',
      'Generator servicing',
      'Security guarding — monthly',
    ];
    const cast = [(3, 2, 9), (7, 5, 9), (3, 3, 4), (7, 4, 4)];

    for (var h = 1; h <= 18; h++) {
      final daysAgo = 20 + h * 6;
      final rejected = h % 9 == 0;
      final (requester, dept, hod) = cast[h % cast.length];
      _addVoucher(
        number: 'PV-2026-${(1100 + h).toString().padLeft(6, '0')}',
        kind: h % 3 == 0 ? 'cash' : 'bank',
        typeId: 101,
        dept: dept,
        requester: requester,
        payee: payees[h % payees.length],
        purpose: purposes[h % purposes.length],
        description:
            'Recurring operational cost, approved against the monthly budget.',
        amount: (2 + (h * 7) % 88) * 100000,
        method: h % 3 == 0 ? 'Cash' : 'Bank Transfer',
        category: const [
          'Logistics',
          'Premises',
          'Transport',
          'Utilities',
        ][h % 4],
        ref: 'INV-${20000 + h}',
        daysAgo: daysAgo,
        status: rejected ? 'rejected' : 'paid',
        step: null,
        paymentRef: rejected ? null : 'TRX-${700000 + h}',
        paidBy: rejected ? null : 'Fatuma Kalinga',
        trail: [
          ('created', requester, null, daysAgo, 7, null, false),
          ('submitted', requester, 1, daysAgo, 8, null, false),
          ('signed', hod, 2, daysAgo - 1, 9, null, true),
          ('forwarded', hod, 2, daysAgo - 1, 10, null, false),
          if (rejected)
            (
              'rejected',
              5,
              3,
              daysAgo - 1,
              14,
              'Outside the approved budget for this period.',
              false,
            )
          else ...[
            ('approved', 5, 3, daysAgo - 1, 15, null, false),
            ('paid', 6, 4, daysAgo - 2, 10, null, false),
          ],
        ],
      );
    }

    _vouchers[0].comments.add(
      MockComment(
        _nextCommentId++,
        4,
        'Within the Q3 logistics budget. The rate matches the framework contract.',
        iso(2, 9, 20),
      ),
    );

    // Seed the inbox from what is actually waiting on each person.
    for (final v in _vouchers) {
      final step = _stepAt(v.currentStepPosition);
      if (step == null) continue;
      _notifyAssignees(v, step);
    }
  }

  void _addVoucher({
    required String number,
    required String kind,
    required int typeId,
    required int dept,
    required int requester,
    required String payee,
    required String purpose,
    required String description,
    required double amount,
    required String method,
    required String category,
    required String ref,
    required int daysAgo,
    required String status,
    required int? step,
    bool signedAtStep = false,
    String? paymentRef,
    String? paidBy,
    List<String> attachments = const [],
    List<(String, int, int?, int, int, String?, bool)> trail = const [],
  }) {
    final id = _nextVoucherId++;
    final v = MockVoucher(
      id: id,
      companyId: 1,
      number: number,
      kind: kind,
      voucherTypeId: typeId,
      departmentId: dept,
      requesterId: requester,
      payee: payee,
      purpose: purpose,
      description: description,
      amount: amount,
      paymentMethod: method,
      category: category,
      accountRef: ref.isEmpty ? null : ref,
      voucherDate: iso(daysAgo).substring(0, 10),
      status: status,
      currentStepPosition: step,
      createdAt: iso(daysAgo, 8),
      attachments: [...attachments],
    );

    for (final (action, actorId, stepPos, ago, hour, comment, signed)
        in trail) {
      final actor = _user(actorId);
      final at = iso(ago, hour);
      _approvals.add(
        MockApproval(
          id: _nextApprovalId++,
          voucherId: id,
          stepPosition: stepPos,
          actorId: actorId,
          actorName: actor?.name ?? '—',
          action: action,
          actedAt: at,
          comment: comment,
          signature: signed ? actor?.signature : null,
        ),
      );
      if (action == 'submitted') v.submittedAt = at;
      if (action == 'approved') v.approvedAt = at;
      if (action == 'rejected') v.rejectedAt = at;
      if (action == 'paid') v.paidAt = at;
      if (action == 'signed' && signedAtStep) v.stepSignedAt = at;
    }

    v.paymentReference = paymentRef;
    v.paidBy = paidBy;
    _vouchers.add(v);
  }
}
