import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/services/admin_repository.dart';
import '../../data/services/api_service.dart';
import '../../widgets/common.dart' show Fmt, showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import 'admin_widgets.dart';

/// The roles an administrator may give, in the web's order and wording.
const employeeRoles = [
  'employee',
  'hod',
  'manager',
  'ceo',
  'cashier',
  'finance',
  'director',
  'company_admin',
];

String employeeRoleLabel(String role) => switch (role) {
  'employee' => 'admin.roleEmployee'.tr,
  'hod' => 'admin.roleHod'.tr,
  'manager' => 'admin.roleManager'.tr,
  'ceo' => 'admin.roleCeo'.tr,
  'cashier' => 'admin.roleCashier'.tr,
  'finance' => 'admin.roleFinance'.tr,
  'director' => 'admin.roleDirector'.tr,
  'company_admin' => 'admin.roleAdmin'.tr,
  _ => role,
};

/// People in the company: search and filter chips, a row per person, and a
/// sheet per person with their details — invite, edit, suspend/activate
/// and delete.
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, this.repository});

  final AdminRepository? repository;

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late final AdminRepository _repo = widget.repository ?? AdminRepository.to;

  int _page = 1;
  String _q = '', _role = '', _status = '', _dept = '';
  Paginated<Employee>? _result;
  List<AdminDepartment> _departments = const [];
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _repo.departments().then((d) {
      if (mounted) setState(() => _departments = d);
    }, onError: (_) {});
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await _repo.employees(
        q: _q,
        role: _role,
        status: _status,
        departmentId: _dept,
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = adminErrorText(e));
    }
  }

  void _filter(void Function() change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  void _search(String q) {
    _q = q;
    _page = 1;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: q.isEmpty ? 0 : 260), _load);
  }

  Future<void> _setStatus(Employee u, String status) async {
    try {
      await _repo.updateEmployee(u.id, {'status': status});
      showToast(
        status == 'suspended'
            ? 'admin.userSuspended'.tr
            : 'admin.userActivated'.tr,
        body: u.name,
        kind: status == 'suspended' ? ToastKind.warn : ToastKind.ok,
      );
      _load();
    } catch (e) {
      adminReport(e, 'admin.couldNotUpdateUser'.tr);
    }
  }

  Future<void> _confirmRemove(Employee u) async {
    final ok = await showVouchFlowDialog<bool>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.trash,
        tone: VfTone.bad,
        title: '${'admin.delete'.tr} ${u.name}?',
        subtitle: 'admin.deleteUserSub'.tr,
        summary: [
          VfSummaryRow('admin.email'.tr, u.email),
          VfSummaryRow('admin.role'.tr, u.roleLabel),
        ],
        actions: [
          Builder(
            builder: (ctx) => VouchFlowButton(
              label: 'admin.cancel'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ),
          Builder(
            builder: (ctx) => VouchFlowButton(
              label: 'admin.delete'.tr,
              icon: PhosphorIconsRegular.trash,
              variant: VfButtonVariant.dangerSolid,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteEmployee(u.id);
      showToast('admin.userRemoved'.tr, body: u.name, kind: ToastKind.warn);
      _load();
    } catch (e) {
      adminReport(e, 'admin.couldNotRemoveUser'.tr);
    }
  }

  Future<void> _openForm([Employee? editing]) async {
    final saved = await showAdminSheet<bool>(
      context,
      (ctx, setSheet) => _EmployeeForm(
        repo: _repo,
        editing: editing,
        departments: _departments,
      ),
    );
    if (saved == true) _load();
  }

  String _statusLabel(String status) => switch (status) {
    'active' => 'admin.active'.tr,
    'invited' => 'admin.invited'.tr,
    'suspended' => 'admin.suspended'.tr,
    _ => status,
  };

  VfTone _statusTone(String status) => status == 'active'
      ? VfTone.ok
      : status == 'invited'
      ? VfTone.info
      : VfTone.bad;

  String _deptName(String id) =>
      _departments.where((d) => '${d.id}' == id).firstOrNull?.name ??
      'admin.allDepartments'.tr;

  Future<void> _pickRole() async {
    final v = await showAdminOptions<String>(
      context,
      title: 'admin.role'.tr,
      selected: _role,
      options: [
        ('', 'admin.allRoles'.tr),
        for (final r in employeeRoles) (r, employeeRoleLabel(r)),
      ],
    );
    if (v != null && v != _role) _filter(() => _role = v);
  }

  Future<void> _pickDept() async {
    final v = await showAdminOptions<String>(
      context,
      title: 'admin.department'.tr,
      selected: _dept,
      options: [
        ('', 'admin.allDepartments'.tr),
        for (final d in _departments) ('${d.id}', d.name),
      ],
    );
    if (v != null && v != _dept) _filter(() => _dept = v);
  }

  /// A person's details and what can be done to them.
  void _openPerson(Employee u) {
    showAdminItemSheet(
      context,
      header: AdminPerson(
        initials: u.initials,
        name: u.name,
        sub: u.email,
        size: 52,
      ),
      details: [
        AdminLine(
          label: 'admin.role'.tr,
          value: [
            u.roleLabel,
            if ((u.jobTitle ?? '').isNotEmpty) u.jobTitle!,
          ].join(' · '),
        ),
        AdminLine(label: 'admin.department'.tr, value: u.departmentName ?? '—'),
        AdminLine(label: 'admin.employeeId'.tr, value: u.employeeCode ?? '—'),
        AdminLine(label: 'admin.vouchers'.tr, value: '${u.voucherCount}'),
        AdminLine(label: 'admin.joined'.tr, value: Fmt.date(u.joinedAt)),
        AdminLine(
          label: 'admin.status'.tr,
          value: '',
          valueWidget: AdminBadge(
            _statusLabel(u.status),
            tone: _statusTone(u.status),
          ),
        ),
        if ((u.phone ?? '').isNotEmpty)
          AdminLine(label: 'admin.phone'.tr, value: u.phone!),
      ],
      actions: [
        AdminSheetAction(
          PhosphorIconsRegular.pencilSimple,
          'admin.edit'.tr,
          () => _openForm(u),
        ),
        u.status != 'suspended'
            ? AdminSheetAction(
                PhosphorIconsRegular.prohibit,
                'admin.suspend'.tr,
                () => _setStatus(u, 'suspended'),
              )
            : AdminSheetAction(
                PhosphorIconsRegular.checkCircle,
                'admin.activate'.tr,
                () => _setStatus(u, 'active'),
              ),
        AdminSheetAction(
          PhosphorIconsRegular.trash,
          'admin.delete'.tr,
          () => _confirmRemove(u),
          danger: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _result?.data ?? const <Employee>[];

    return AdminPageBody(
      route: '/employees',
      title: 'admin.employees'.tr,
      onRefresh: _load,
      action: AdminRoundAction(
        icon: PhosphorIconsBold.userPlus,
        label: 'admin.inviteUser'.tr,
        onPressed: () => _openForm(),
      ),
      children: [
        AdminSearchField(placeholder: 'admin.search'.tr, onChanged: _search),
        const SizedBox(height: 12),
        AdminChipRail(
          children: [
            for (final s in const ['', 'active', 'invited', 'suspended'])
              VouchFlowFilterChip(
                label: s.isEmpty ? 'admin.allStatuses'.tr : _statusLabel(s),
                selected: _status == s,
                onTap: () => _filter(() => _status = s),
              ),
            AdminSelectChip(
              label: _role.isEmpty ? 'admin.role'.tr : employeeRoleLabel(_role),
              active: _role.isNotEmpty,
              onTap: _pickRole,
              onClear: () => _filter(() => _role = ''),
            ),
            if (_departments.isNotEmpty)
              AdminSelectChip(
                label: _dept.isEmpty ? 'admin.department'.tr : _deptName(_dept),
                active: _dept.isNotEmpty,
                onTap: _pickDept,
                onClear: () => _filter(() => _dept = ''),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (_result == null)
          const VouchFlowLoadingState(rows: 6, rowHeight: 72)
        else if (rows.isEmpty)
          VouchFlowCard(
            radius: VfSize.radiusXl,
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.usersThree,
              title: 'admin.noResults'.tr,
            ),
          )
        else ...[
          for (final u in rows)
            AdminListRow(
              semanticLabel: '${'admin.actions'.tr}: ${u.name}',
              leading: VouchFlowAvatar(
                initials: u.initials.isEmpty ? '?' : u.initials,
                size: 44,
              ),
              title: u.name,
              meta: [
                u.roleLabel,
                if ((u.departmentName ?? '').isNotEmpty) u.departmentName!,
              ].join(' · '),
              trailing: u.status == 'active'
                  ? const AdminChevron()
                  : AdminBadge(
                      _statusLabel(u.status),
                      tone: _statusTone(u.status),
                    ),
              onTap: () => _openPerson(u),
            ),
          AdminPagination(
            page: _result!.page,
            lastPage: _result!.lastPage,
            total: _result!.total,
            onChange: (p) {
              setState(() => _page = p);
              _load();
            },
          ),
        ],
      ],
    );
  }
}

/// Invite or edit a person — the web's Employees dialog.
class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({
    required this.repo,
    required this.editing,
    required this.departments,
  });

  final AdminRepository repo;
  final Employee? editing;
  final List<AdminDepartment> departments;

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  late final Employee? e = widget.editing;
  late final _name = TextEditingController(text: e?.name ?? '');
  late final _email = TextEditingController(text: e?.email ?? '');
  late final _phone = TextEditingController(text: e?.phone ?? '');
  late final _code = TextEditingController(text: e?.employeeCode ?? '');
  late final _title = TextEditingController(text: e?.jobTitle ?? '');
  late String _role = e?.role ?? 'employee';
  late String _dept = e?.departmentId == null ? '' : '${e!.departmentId}';
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _email]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _code, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'name': _name.text,
      'email': _email.text,
      'phone': _phone.text,
      'employee_code': _code.text,
      'job_title': _title.text,
      'role': _role,
      'department_id': _dept.isEmpty ? null : int.parse(_dept),
    };
    try {
      if (e == null) {
        final (user, password) = await widget.repo.inviteEmployee(body);
        showToast(
          'admin.invitationCreated'.tr,
          body: password != null
              ? fill('admin.tempPasswordFor'.tr, {
                  'name': user.name,
                  'password': password,
                })
              : fill('admin.hasBeenInvited'.tr, {'name': user.name}),
        );
      } else {
        await widget.repo.updateEmployee(e!.id, body);
        showToast(
          'admin.updated'.tr,
          body: fill('admin.nameSaved'.tr, {'name': _name.text}),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (err is ApiException && mounted) setState(() => _error = err);
      adminReport(err, 'admin.couldNotSaveUser'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? fe(String k) => _error?.field(k);
    const gap = SizedBox(height: 12);
    return VouchFlowDialog(
      title: e == null ? 'admin.inviteUser'.tr : 'admin.edit'.tr,
      icon: e == null
          ? PhosphorIconsRegular.userPlus
          : PhosphorIconsRegular.pencilSimple,
      tone: VfTone.primary,
      actions: [
        VouchFlowButton(
          label: 'admin.cancel'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        VouchFlowButton(
          label: 'admin.save'.tr,
          loading: _busy,
          onPressed: _busy || _name.text.isEmpty || _email.text.isEmpty
              ? null
              : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowTextField(
            label: 'admin.fullName'.tr,
            controller: _name,
            required: true,
            error: fe('name'),
            textInputAction: TextInputAction.next,
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.email'.tr,
            controller: _email,
            required: true,
            error: fe('email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.phone'.tr,
            controller: _phone,
            keyboardType: TextInputType.phone,
            error: fe('phone'),
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.employeeId'.tr,
            controller: _code,
            error: fe('employee_code'),
          ),
          gap,
          VouchFlowDropdown<String>(
            label: 'admin.role'.tr,
            required: true,
            items: employeeRoles,
            value: _role,
            itemLabel: employeeRoleLabel,
            error: fe('role'),
            onChanged: (v) => setState(() => _role = v ?? 'employee'),
          ),
          gap,
          VouchFlowDropdown<String>(
            label: 'admin.department'.tr,
            items: ['', for (final d in widget.departments) '${d.id}'],
            value: _dept,
            itemLabel: (v) => v.isEmpty
                ? '—'
                : widget.departments.firstWhere((d) => '${d.id}' == v).name,
            error: fe('department_id'),
            onChanged: (v) => setState(() => _dept = v ?? ''),
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.jobTitle'.tr,
            controller: _title,
            error: fe('job_title'),
          ),
          if (e == null) ...[gap, AdminNote('admin.tempPasswordNote'.tr)],
        ],
      ),
    );
  }
}
