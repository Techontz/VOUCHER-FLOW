import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/services/admin_repository.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart' show Fmt, showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import 'admin_widgets.dart';

/// A workflow role's name, as the web's ROLE_KEYS spell it.
String wfcRoleName(String role) => switch (role) {
  'employee' => 'admin.wfcRoleEmployee'.tr,
  'hod' => 'admin.wfcRoleHod'.tr,
  'manager' => 'admin.wfcRoleManager'.tr,
  'finance' => 'admin.wfcRoleFinance'.tr,
  'ceo' => 'admin.wfcRoleCeo'.tr,
  'cashier' => 'admin.wfcRoleCashier'.tr,
  'director' => 'admin.wfcRoleDirector'.tr,
  'company_admin' => 'admin.wfcRoleAdmin'.tr,
  'custom' => 'admin.wfcSpecificPerson'.tr,
  _ => role,
};

/// Departments: a row per department (people and spend this quarter), and
/// a sheet with its head (who signs), manager (who approves), vouchers —
/// with search, add, edit and delete.
class DepartmentsPage extends StatefulWidget {
  const DepartmentsPage({super.key, this.repository});

  final AdminRepository? repository;

  @override
  State<DepartmentsPage> createState() => _DepartmentsPageState();
}

class _DepartmentsPageState extends State<DepartmentsPage> {
  late final AdminRepository _repo = widget.repository ?? AdminRepository.to;
  final _searchCtl = TextEditingController();

  List<AdminDepartment>? _rows;
  List<DirectoryUser> _people = const [];
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    _repo.directory().then((p) {
      if (mounted) setState(() => _people = p);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await _repo.departments();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorText(e));
    }
  }

  Future<void> _openForm([AdminDepartment? editing]) async {
    final saved = await showAdminSheet<bool>(
      context,
      (ctx, _) =>
          _DepartmentForm(repo: _repo, editing: editing, people: _people),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmRemove(AdminDepartment d) async {
    final ok = await showVouchFlowDialog<bool>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.trash,
        tone: VfTone.bad,
        title: '${'admin.delete'.tr} ${d.name}?',
        subtitle: 'admin.deleteDeptSub'.tr,
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
      await _repo.deleteDepartment(d.id);
      showToast('admin.deptDeleted'.tr, body: d.name, kind: ToastKind.warn);
      _load();
    } catch (e) {
      adminReport(e, 'admin.couldNotDeleteDept'.tr);
    }
  }

  /// A seat that needs attention: nobody in it, or someone inactive.
  static bool _seatGap(SeatHolder? p) =>
      p == null || (p.status != null && p.status != 'active');

  void _openDept(AdminDepartment d, String currency) {
    showAdminItemSheet(
      context,
      header: Row(
        children: [
          const AdminIconTile(PhosphorIconsRegular.treeStructure, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  style: VfType.sectionTitle.copyWith(color: context.vf.text),
                ),
                if ((d.costCentre ?? d.code ?? '').isNotEmpty)
                  Text(
                    [
                      if ((d.code ?? '').isNotEmpty) d.code!,
                      if ((d.costCentre ?? '').isNotEmpty) d.costCentre!,
                    ].join(' · '),
                    style: VfType.small.copyWith(color: context.vf.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
      details: [
        AdminLine(
          label: 'admin.headOfDept'.tr,
          value: '',
          valueWidget: _Assigned(d.hod),
        ),
        AdminLine(
          label: 'admin.approvingManager'.tr,
          value: '',
          valueWidget: _Assigned(d.manager),
        ),
        AdminLine(label: 'admin.people'.tr, value: '${d.usersCount}'),
        AdminLine(label: 'admin.vouchers'.tr, value: '${d.vouchersCount}'),
        AdminLine(
          label: 'admin.spendQuarter'.tr,
          value: Fmt.money(d.spend, currency),
          strong: true,
        ),
      ],
      actions: [
        AdminSheetAction(
          PhosphorIconsRegular.pencilSimple,
          'admin.edit'.tr,
          () => _openForm(d),
        ),
        AdminSheetAction(
          PhosphorIconsRegular.trash,
          'admin.delete'.tr,
          () => _confirmRemove(d),
          danger: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rows = _rows;
    final term = _search.trim().toLowerCase();
    // The whole list is already loaded, so search filters it here: by name,
    // code, cost centre, head or manager.
    final shown = rows == null || term.isEmpty
        ? rows
        : rows
              .where(
                (d) => [
                  d.name,
                  d.code,
                  d.costCentre,
                  d.hod?.name,
                  d.manager?.name,
                ].any((f) => f?.toLowerCase().contains(term) ?? false),
              )
              .toList();
    final currency = Get.isRegistered<SessionService>()
        ? Get.find<SessionService>().company.value?.currency ?? 'TZS'
        : 'TZS';

    return AdminPageBody(
      route: '/departments',
      title: 'admin.departments'.tr,
      onRefresh: _load,
      action: AdminRoundAction(
        icon: PhosphorIconsBold.plus,
        label: 'admin.addDepartment'.tr,
        onPressed: () => _openForm(),
      ),
      children: [
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (rows == null)
          const VouchFlowLoadingState(rows: 5, rowHeight: 72)
        else if (rows.isEmpty)
          VouchFlowCard(
            radius: VfSize.radiusXl,
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.treeStructure,
              title: 'admin.noDepartmentsYet'.tr,
              actionLabel: 'admin.addDepartment'.tr,
              onAction: () => _openForm(),
            ),
          )
        else ...[
          AdminSearchField(
            controller: _searchCtl,
            placeholder: 'admin.searchDepartments'.tr,
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 16),
          if (shown!.isEmpty)
            VouchFlowCard(
              radius: VfSize.radiusXl,
              child: VouchFlowEmptyState(
                icon: PhosphorIconsRegular.magnifyingGlass,
                title: 'admin.noResults'.tr,
                actionLabel: 'admin.clearFilters'.tr,
                onAction: () {
                  _searchCtl.clear();
                  setState(() => _search = '');
                },
              ),
            )
          else
            for (final d in shown)
              AdminListRow(
                semanticLabel: d.name,
                leading: const AdminIconTile(
                  PhosphorIconsRegular.treeStructure,
                ),
                title: d.name,
                meta:
                    '${d.usersCount} ${'admin.people'.tr.toLowerCase()} · ${Fmt.money(d.spend, currency)}',
                trailing: _seatGap(d.hod) || _seatGap(d.manager)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsFill.warningCircle,
                            size: 18,
                            color: t.warningStrong,
                            semanticLabel: 'admin.wfcDeptNotAssigned'.tr,
                          ),
                          const SizedBox(width: 6),
                          const AdminChevron(),
                        ],
                      )
                    : const AdminChevron(),
                onTap: () => _openDept(d, currency),
              ),
        ],
      ],
    );
  }
}

/// Who holds a seat, flagged when unset or inactive.
class _Assigned extends StatelessWidget {
  const _Assigned(this.person);
  final SeatHolder? person;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = person;
    if (p == null) {
      return AdminBadge('admin.wfcDeptNotAssigned'.tr, tone: VfTone.warn);
    }
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          p.name,
          textAlign: TextAlign.right,
          style: VfType.small.copyWith(
            color: t.text,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (p.status != null && p.status != 'active')
          AdminBadge('admin.wfcInactive'.tr, tone: VfTone.warn),
      ],
    );
  }
}

/// Add or edit a department — the web's dialog. Only active people are
/// offered; a head since deactivated stays visible (and flagged) until
/// someone active replaces them.
class _DepartmentForm extends StatefulWidget {
  const _DepartmentForm({
    required this.repo,
    required this.editing,
    required this.people,
  });

  final AdminRepository repo;
  final AdminDepartment? editing;
  final List<DirectoryUser> people;

  @override
  State<_DepartmentForm> createState() => _DepartmentFormState();
}

class _DepartmentFormState extends State<_DepartmentForm> {
  late final AdminDepartment? d = widget.editing;
  late final _name = TextEditingController(text: d?.name ?? '')
    ..addListener(() => setState(() {}));
  late final _code = TextEditingController(text: d?.code ?? '');
  late final _cc = TextEditingController(text: d?.costCentre ?? '');
  late String _hod = d?.hodUserId == null ? '' : '${d!.hodUserId}';
  late String _mgr = d?.managerUserId == null ? '' : '${d!.managerUserId}';
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _cc.dispose();
    super.dispose();
  }

  /// The saved person is no longer among the active users offered.
  bool _inactive(String value, SeatHolder? saved) =>
      value.isNotEmpty &&
      saved != null &&
      '${saved.id}' == value &&
      widget.people.isNotEmpty &&
      !widget.people.any((p) => '${p.id}' == value);

  String _label(DirectoryUser p) => '${p.name} · ${wfcRoleName(p.role)}';

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.saveDepartment(d?.id, {
        'name': _name.text,
        'code': _code.text,
        'cost_centre': _cc.text,
        'hod_user_id': _hod.isEmpty ? null : int.parse(_hod),
        'manager_user_id': _mgr.isEmpty ? null : int.parse(_mgr),
      });
      showToast(
        d != null ? 'admin.deptUpdated'.tr : 'admin.deptCreated'.tr,
        body: _name.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (e is ApiException && mounted) setState(() => _error = e);
      adminReport(e, 'admin.couldNotSaveDept'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _seat({
    required String label,
    required String value,
    required SeatHolder? saved,
    required String field,
    required ValueChanged<String> onChanged,
  }) {
    final inactive = _inactive(value, saved);
    final items = [
      '',
      if (inactive) value,
      for (final p in widget.people) '${p.id}',
    ];
    return VouchFlowDropdown<String>(
      label: label,
      error: inactive ? 'admin.wfcDeptPersonInactive'.tr : _error?.field(field),
      items: items,
      value: value,
      itemLabel: (v) {
        if (v.isEmpty) return 'admin.wfcDeptNotAssigned'.tr;
        final p = widget.people.where((p) => '${p.id}' == v).firstOrNull;
        return p != null
            ? _label(p)
            : '${saved?.name ?? '—'} (${'admin.wfcInactive'.tr})';
      },
      onChanged: (v) {
        // The inactive holder is shown, not chosen again.
        if (v != null && _inactive(v, saved) && v != value) return;
        onChanged(v ?? '');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return VouchFlowDialog(
      title: d != null ? 'admin.edit'.tr : 'admin.addDepartment'.tr,
      icon: PhosphorIconsRegular.treeStructure,
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
          onPressed: _busy || _name.text.isEmpty ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowTextField(
            label: 'admin.department'.tr,
            controller: _name,
            required: true,
            error: _error?.field('name'),
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: VouchFlowTextField(
                  label: 'admin.code'.tr,
                  controller: _code,
                  error: _error?.field('code'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: VouchFlowTextField(
                  label: 'admin.costCentre'.tr,
                  controller: _cc,
                  error: _error?.field('cost_centre'),
                ),
              ),
            ],
          ),
          gap,
          _seat(
            label: 'admin.wfcDeptHodSigns'.tr,
            value: _hod,
            saved: d?.hod,
            field: 'hod_user_id',
            onChanged: (v) => setState(() => _hod = v),
          ),
          gap,
          _seat(
            label: 'admin.wfcDeptManagerApproves'.tr,
            value: _mgr,
            saved: d?.manager,
            field: 'manager_user_id',
            onChanged: (v) => setState(() => _mgr = v),
          ),
        ],
      ),
    );
  }
}
