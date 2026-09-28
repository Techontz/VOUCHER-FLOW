import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/services/admin_repository.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../shell/shell_page.dart';
import 'admin_widgets.dart';
import 'departments_page.dart' show wfcRoleName;

/// The approval workflow builder — the web's settings/workflow-builder.tsx:
/// which workflows the company runs, which voucher types each routes, and —
/// level by level — who acts, in what order, for which amounts and with
/// which permissions. Below the route: who that resolves to in every
/// department, and the same permissions as a matrix.

/// Roles a non-request level may be given; "custom" is "Specific person".
const _levelRoles = ['hod', 'manager', 'ceo', 'finance', 'director', 'cashier'];

/// Every capability a step stores — and every one is sent back on save.
const _caps = [
  ('can_sign', 'admin.capSign', PhosphorIconsRegular.signature),
  ('can_approve', 'admin.capApprove', PhosphorIconsRegular.sealCheck),
  ('can_reject', 'admin.capReject', PhosphorIconsRegular.xCircle),
  (
    'can_request_changes',
    'admin.capRequestChanges',
    PhosphorIconsRegular.arrowUUpLeft,
  ),
  ('can_pay', 'admin.capPay', PhosphorIconsRegular.wallet),
  ('can_print', 'admin.capPrint', PhosphorIconsRegular.printer),
  ('can_download', 'admin.capDownload', PhosphorIconsRegular.downloadSimple),
];

const _gapKeys = {
  'no_hod': 'admin.wfcGapNoHod',
  'inactive_hod': 'admin.wfcGapInactiveHod',
  'no_manager': 'admin.wfcGapNoManager',
  'inactive_manager': 'admin.wfcGapInactiveManager',
  'inactive_person': 'admin.wfcGapInactivePerson',
  'missing_person': 'admin.wfcGapMissingPerson',
  'no_person_named': 'admin.wfcGapNoPerson',
  'no_one_with_role': 'admin.wfcGapNoRole',
};

/// Gaps an administrator fixes on the Departments page rather than here.
const _departmentGaps = [
  'no_hod',
  'inactive_hod',
  'no_manager',
  'inactive_manager',
];

final _amount = NumberFormat('#,##0.##', 'en_US');

class WorkflowBuilder extends StatefulWidget {
  const WorkflowBuilder({super.key, this.repository});

  final AdminRepository? repository;

  @override
  State<WorkflowBuilder> createState() => WorkflowBuilderState();
}

class WorkflowBuilderState extends State<WorkflowBuilder> {
  late final AdminRepository _repo = widget.repository ?? AdminRepository.to;

  List<Workflow>? _workflows;
  Workflow? _current;
  List<WorkflowStep> _steps = [];
  List<DirectoryUser> _people = const [];
  List<AdminDepartment> _departments = const [];
  List<AdminVoucherType> _types = const [];
  List<WorkflowPreset> _presets = const [];
  WorkflowRouting? _routing;
  (int, int)? _routingFor;
  bool _busy = false;
  String? _error;
  int? _open;
  bool _dirty = false;
  int _selectNonce = 0;

  String get _locale => Get.locale?.languageCode ?? 'en';

  @override
  void initState() {
    super.initState();
    _load();
    _repo.directory().then((v) => _set(() => _people = v), onError: (_) {});
    _repo.departments().then(
      (v) => _set(() => _departments = v),
      onError: (_) {},
    );
    _repo.voucherTypes().then((v) => _set(() => _types = v), onError: (_) {});
    _repo.presets().then((v) => _set(() => _presets = v), onError: (_) {});
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  Future<void> reload() => _load(_current?.id);

  void _pick(Workflow? wf) {
    setState(() {
      _current = wf?.copy();
      _steps = wf == null ? [] : [for (final s in wf.steps) s.copy()];
      _dirty = false;
      _open = null;
    });
    _loadRouting();
  }

  Future<void> _load([int? keepId]) async {
    try {
      final list = await _repo.workflows();
      if (!mounted) return;
      setState(() {
        _error = null;
        _workflows = list;
      });
      final keep = keepId == null
          ? null
          : list.where((w) => w.id == keepId).firstOrNull;
      _pick(
        keep ?? list.where((w) => w.isDefault).firstOrNull ?? list.firstOrNull,
      );
    } catch (e) {
      _set(() => _error = adminErrorText(e));
    }
  }

  /// The matrix reflects the saved workflow, so it reloads per version.
  Future<void> _loadRouting() async {
    final wf = _current;
    if (wf == null) return;
    final key = (wf.id, wf.version);
    if (_routingFor == key && _routing != null) return;
    try {
      final r = await _repo.routing(wf.id);
      _set(() {
        _routing = r;
        _routingFor = key;
      });
    } catch (_) {
      _set(() {
        _routing = null;
        _routingFor = key;
      });
    }
  }

  void _patch(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  void _move(int index, int direction) {
    final target = index + direction;
    // The request step stays first — it is the requester's own step.
    if (index == 0 || target < 1 || target >= _steps.length) return;
    _patch(() {
      final s = _steps.removeAt(index);
      _steps.insert(target, s);
      _open = target;
    });
  }

  void _addStep() => _patch(() {
    _steps.add(WorkflowStep(name: 'New level', role: 'finance'));
    _open = _steps.length - 1;
  });

  void _removeStep(int index) => _patch(() {
    _steps.removeAt(index);
    _open = null;
  });

  Future<void> _save() async {
    final wf = _current;
    if (wf == null) return;
    setState(() => _busy = true);
    try {
      final saved = await _repo.saveWorkflow(
        wf.id,
        workflowPayload(wf, _steps),
      );
      showToast('admin.wfcSaved'.tr, body: 'admin.wfcSavedSub'.tr);
      await _load(saved.id);
    } catch (e) {
      adminReport(e, 'admin.couldNotSaveWorkflow'.tr);
    } finally {
      _set(() => _busy = false);
    }
  }

  Future<bool> _applyPreset(String key) async {
    setState(() => _busy = true);
    try {
      final wf = await _repo.applyPreset(key);
      showToast('admin.workflowApplied'.tr, body: wf.routeSummary ?? wf.name);
      await _load(wf.id);
      return true;
    } catch (e) {
      adminReport(e, 'admin.couldNotApplyPreset'.tr);
      return false;
    } finally {
      _set(() => _busy = false);
    }
  }

  Future<bool> _create(_WorkflowFieldsValue fields, String source) async {
    final base = _workflows?.where((w) => w.isDefault).firstOrNull;
    setState(() => _busy = true);
    try {
      final draft = Workflow(
        id: 0,
        name: fields.name.trim(),
        nameSw: fields.nameSw.trim().isEmpty ? null : fields.nameSw.trim(),
        description: fields.description.trim().isEmpty
            ? null
            : fields.description.trim(),
        voucherTypeId: fields.voucherTypeId,
        isDefault: false,
        isActive: true,
      );
      final Map<String, dynamic> body;
      if (source == 'copy' && base != null) {
        body = workflowPayload(draft, base.steps, includeIds: false);
      } else {
        body = {
          'name': draft.name,
          'name_sw': draft.nameSw,
          'description': draft.description,
          'voucher_type_id': draft.voucherTypeId,
          'is_default': false,
          'is_active': true,
          'from_preset': source == 'copy' ? 'default' : source,
        };
      }
      final wf = await _repo.createWorkflow(body);
      showToast('admin.wfcCreated'.tr, body: wf.name);
      await _load(wf.id);
      return true;
    } catch (e) {
      adminReport(e, 'admin.couldNotCreateWorkflow'.tr);
      return false;
    } finally {
      _set(() => _busy = false);
    }
  }

  Future<void> _makeDefault() async {
    final wf = _current;
    if (wf == null) return;
    setState(() => _busy = true);
    try {
      final r = await _repo.makeDefault(wf.id);
      showToast('admin.wfcMadeDefault'.tr, body: r.name);
      await _load(r.id);
    } catch (e) {
      adminReport(e, 'admin.couldNotChangeDefault'.tr);
    } finally {
      _set(() => _busy = false);
    }
  }

  Future<bool> _remove() async {
    final wf = _current;
    if (wf == null) return false;
    setState(() => _busy = true);
    try {
      await _repo.deleteWorkflow(wf.id);
      showToast('admin.wfcDeleted'.tr, body: wf.name, kind: ToastKind.warn);
      await _load();
      return true;
    } catch (e) {
      adminReport(e, 'admin.couldNotDeleteWorkflow'.tr);
      return false;
    } finally {
      _set(() => _busy = false);
    }
  }

  /* ── helpers ── */

  String _typeName(AdminVoucherType t) => t.label(_locale);

  String? _deptName(int? id) =>
      _departments.where((d) => d.id == id).firstOrNull?.name;

  String _personLabel(DirectoryUser p) => [
    p.name,
    wfcRoleName(p.role),
    _deptName(p.departmentId),
  ].whereType<String>().join(' · ');

  /// What is wrong with the person side of a level, if anything.
  String? _personIssue(WorkflowStep step) {
    if (step.assignedUserId != null) {
      if (_people.any((p) => p.id == step.assignedUserId)) return null;
      final known = step.assignedUser?.id == step.assignedUserId
          ? step.assignedUser
          : null;
      // /directory lists active users only; a named person missing from it is inactive or gone.
      if (known != null) {
        return fill('admin.wfcPersonInactive'.tr, {'name': known.name});
      }
      return _people.isNotEmpty ? 'admin.wfcPersonMissing'.tr : null;
    }
    return step.role == 'custom' ? 'admin.wfcNoPersonChosen'.tr : null;
  }

  String _whoSummary(WorkflowStep step, int index) {
    if (index == 0) return 'admin.wfcRequester'.tr;
    if (step.assignedUserId != null) {
      return _people
              .where((p) => p.id == step.assignedUserId)
              .firstOrNull
              ?.name ??
          step.assignedUser?.name ??
          'admin.wfcSpecificPerson'.tr;
    }
    if (step.role == 'hod') return 'admin.wfcEachHod'.tr;
    if (step.role == 'manager') return 'admin.wfcEachManager'.tr;
    if (step.role == 'custom') return 'admin.wfcNoPersonChosen'.tr;
    return fill('admin.wfcEveryoneWithRole'.tr, {
      'role': wfcRoleName(step.role),
    });
  }

  String? _band(WorkflowStep s) {
    if (s.minAmount == null && s.maxAmount == null) return null;
    return [
      if (s.minAmount != null)
        fill('admin.bandFrom'.tr, {'amount': _amount.format(s.minAmount)}),
      if (s.maxAmount != null)
        fill('admin.bandUpTo'.tr, {'amount': _amount.format(s.maxAmount)}),
    ].join(' ');
  }

  bool _bandInvalid(WorkflowStep s) =>
      s.minAmount != null && s.maxAmount != null && s.minAmount! > s.maxAmount!;

  /* ── dialogs ── */

  Future<void> _switchTo(Workflow? next) async {
    if (!_dirty) {
      _pick(next);
      return;
    }
    final wf = _current!;
    final discard = await showVouchFlowDialog<bool>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.warning,
        tone: VfTone.warn,
        title: 'admin.discardTitle'.tr,
        subtitle: fill('admin.discardSub'.tr, {'name': wf.name}),
        actions: [
          Builder(
            builder: (c) => VouchFlowButton(
              label: 'admin.keepEditing'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: () => Navigator.of(c).pop(false),
            ),
          ),
          Builder(
            builder: (c) => VouchFlowButton(
              label: 'admin.discardChanges'.tr,
              variant: VfButtonVariant.dangerSolid,
              onPressed: () => Navigator.of(c).pop(true),
            ),
          ),
        ],
      ),
    );
    if (discard == true) {
      _pick(next);
    } else {
      setState(() => _selectNonce++);
    }
  }

  List<int> _clashes(Iterable<Workflow> among) => [
    for (final w in among)
      if (w.isActive && w.voucherTypeId != null) w.voucherTypeId!,
  ];

  Future<void> _openDetails() async {
    final wf = _current;
    if (wf == null) return;
    final value = _WorkflowFieldsValue(
      name: wf.name,
      nameSw: wf.nameSw ?? '',
      description: wf.description ?? '',
      voucherTypeId: wf.voucherTypeId,
    );
    final others = _workflows!.where((w) => w.id != wf.id);
    final applied = await showAdminSheet<bool>(
      context,
      (ctx, setSheet) => VouchFlowDialog(
        icon: PhosphorIconsRegular.pencilSimple,
        tone: VfTone.primary,
        title: 'admin.wfcDetailsTitle'.tr,
        actions: [
          VouchFlowButton(
            label: 'admin.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          VouchFlowButton(
            label: 'admin.confirm'.tr,
            onPressed: value.name.trim().isEmpty
                ? null
                : () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: _WorkflowFields(
          value: value,
          onChanged: () => setSheet(() {}),
          types: _types,
          typeName: _typeName,
          lockType: wf.isDefault,
          clashes: _clashes(others),
        ),
      ),
    );
    if (applied != true) return;
    // Details are applied to the draft; they are saved with the route.
    final type = _types.where((t) => t.id == value.voucherTypeId).firstOrNull;
    _patch(() {
      wf.name = value.name.trim().isEmpty ? wf.name : value.name.trim();
      wf.nameSw = value.nameSw.trim().isEmpty ? null : value.nameSw.trim();
      wf.description = value.description.trim().isEmpty
          ? null
          : value.description.trim();
      wf.voucherTypeId = value.voucherTypeId;
      wf.voucherTypeName = type?.name;
      wf.voucherTypeNameSw = type?.nameSw;
    });
  }

  Future<void> _openCreate() async {
    final value = _WorkflowFieldsValue();
    var source = 'copy';
    var busy = false;
    await showAdminSheet<void>(
      context,
      (ctx, setSheet) => VouchFlowDialog(
        icon: PhosphorIconsRegular.flowArrow,
        tone: VfTone.primary,
        title: 'admin.wfcNewWorkflow'.tr,
        actions: [
          VouchFlowButton(
            label: 'admin.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: busy ? null : () => Navigator.of(ctx).pop(),
          ),
          VouchFlowButton(
            label: 'admin.wfcCreate'.tr,
            loading: busy,
            onPressed: busy || value.name.trim().isEmpty
                ? null
                : () async {
                    setSheet(() => busy = true);
                    final ok = await _create(value, source);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.of(ctx).pop();
                    } else {
                      setSheet(() => busy = false);
                    }
                  },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkflowFields(
              value: value,
              onChanged: () => setSheet(() {}),
              types: _types,
              typeName: _typeName,
              lockType: false,
              clashes: _clashes(_workflows!),
            ),
            const SizedBox(height: 16),
            Text(
              'admin.wfcStartFrom'.tr,
              style: VfType.label.copyWith(color: ctx.vf.text2),
            ),
            const SizedBox(height: 8),
            VouchFlowSelectCard(
              title: 'admin.wfcCopyDefault'.tr,
              subtitle: 'admin.wfcCopyDefaultSub'.tr,
              icon: PhosphorIconsRegular.copy,
              selected: source == 'copy',
              onTap: () => setSheet(() => source = 'copy'),
            ),
            for (final p in _presets) ...[
              const SizedBox(height: 8),
              VouchFlowSelectCard(
                title: p.name,
                subtitle: p.description,
                icon: PhosphorIconsRegular.flowArrow,
                selected: source == p.key,
                onTap: () => setSheet(() => source = p.key),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDelete() async {
    final wf = _current!;
    final list = _workflows!;
    final block = list.length <= 1
        ? 'admin.wfcCannotDeleteOnly'.tr
        : wf.isDefault
        ? 'admin.wfcCannotDeleteDefault'.tr
        : wf.inFlightCount > 0
        ? fill('admin.wfcCannotDeleteInFlight'.tr, {'count': wf.inFlightCount})
        : wf.vouchersCount > 0
        ? 'admin.wfcCannotDeleteUsed'.tr
        : null;
    var busy = false;
    await showAdminSheet<void>(
      context,
      (ctx, setSheet) => VouchFlowDialog(
        icon: PhosphorIconsRegular.trash,
        tone: VfTone.bad,
        title: 'admin.wfcDeleteTitle'.tr,
        subtitle: block == null ? 'admin.wfcDeleteSub'.tr : null,
        actions: [
          VouchFlowButton(
            label: 'admin.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: busy ? null : () => Navigator.of(ctx).pop(),
          ),
          if (block == null)
            VouchFlowButton(
              label: 'admin.delete'.tr,
              icon: PhosphorIconsRegular.trash,
              variant: VfButtonVariant.dangerSolid,
              loading: busy,
              onPressed: busy
                  ? null
                  : () async {
                      setSheet(() => busy = true);
                      final ok = await _remove();
                      if (!ctx.mounted) return;
                      if (ok) {
                        Navigator.of(ctx).pop();
                      } else {
                        setSheet(() => busy = false);
                      }
                    },
            ),
        ],
        child: block == null ? null : AdminNote(block, tone: VfTone.warn),
      ),
    );
  }

  Future<void> _openPresets() async {
    String? chosen;
    var busy = false;
    await showAdminSheet<void>(
      context,
      (ctx, setSheet) => VouchFlowDialog(
        icon: PhosphorIconsRegular.magicWand,
        tone: VfTone.primary,
        title: 'admin.presets'.tr,
        subtitle: 'admin.presetsSub'.tr,
        actions: [
          VouchFlowButton(
            label: 'admin.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: busy ? null : () => Navigator.of(ctx).pop(),
          ),
          VouchFlowButton(
            label: 'admin.applyPreset'.tr,
            loading: busy,
            onPressed: busy || chosen == null
                ? null
                : () async {
                    setSheet(() => busy = true);
                    final ok = await _applyPreset(chosen!);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.of(ctx).pop();
                    } else {
                      setSheet(() => busy = false);
                    }
                  },
          ),
        ],
        child: Column(
          children: [
            for (final p in _presets) ...[
              VouchFlowSelectCard(
                title: p.name,
                subtitle: p.description,
                icon: PhosphorIconsRegular.flowArrow,
                selected: chosen == p.key,
                onTap: () => setSheet(() => chosen = p.key),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  /* ── build ── */

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    if (_error != null) {
      return VouchFlowErrorState(
        message: _error!,
        onRetry: () => _load(),
        retryLabel: 'action.retry'.tr,
      );
    }
    final workflows = _workflows;
    if (workflows == null) {
      return const VouchFlowLoadingState(rows: 5, rowHeight: 90);
    }
    final wf = _current;
    if (wf == null) {
      return VouchFlowCard(
        child: VouchFlowEmptyState(
          icon: PhosphorIconsRegular.flowArrow,
          title: 'admin.noWorkflow'.tr,
          body: 'admin.noWorkflowBody'.tr,
          actionLabel: 'admin.presets'.tr,
          onAction: _openPresets,
        ),
      );
    }

    final levels = _steps.length > 1
        ? _steps.sublist(1)
        : const <WorkflowStep>[];
    final noPayer = _steps.length > 1 && !levels.any((s) => s.canPay);
    final noDecider = _steps.length > 1 && !levels.any((s) => s.canApprove);
    final appliesTo = wf.typeLabel(_locale) ?? 'admin.wfcAllTypes'.tr;
    final company = Get.isRegistered<SessionService>()
        ? Get.find<SessionService>().company.value?.name
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _head(t, wf, workflows, appliesTo),
        if (noPayer || noDecider) ...[
          const SizedBox(height: 12),
          VouchFlowAlert(
            tone: VfTone.warn,
            icon: PhosphorIconsRegular.warning,
            message: [
              if (noDecider) 'admin.wfcNoApprover'.tr,
              if (noPayer) 'admin.wfcNoPayer'.tr,
            ].join('\n'),
          ),
        ],
        const SizedBox(height: 16),
        _flow(t),
        const SizedBox(height: 16),
        _routingPanel(t, wf),
        const SizedBox(height: 16),
        _matrix(t),
        const SizedBox(height: 16),
        AdminNote(
          company == null
              ? 'admin.isolationNote'.tr
              : 'admin.isolationNote'.tr.replaceAll('this company', company),
        ),
      ],
    );
  }

  Widget _head(
    VfTokens t,
    Workflow wf,
    List<Workflow> workflows,
    String appliesTo,
  ) {
    return VouchFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workflows.length > 1)
            Semantics(
              label: 'admin.workflow'.tr,
              child: DropdownButtonFormField<int>(
                key: ValueKey('wf|${wf.id}|$_selectNonce'),
                initialValue: wf.id,
                isExpanded: true,
                icon: Icon(
                  PhosphorIconsRegular.caretDown,
                  size: 16,
                  color: t.muted,
                ),
                dropdownColor: t.surface,
                borderRadius: BorderRadius.circular(VfSize.radiusL),
                style: VfType.bodyStrong.copyWith(color: t.text),
                decoration: InputDecoration(filled: true, fillColor: t.inputBg),
                items: [
                  for (final w in workflows)
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(
                        [
                          w.name,
                          if (w.isDefault) 'admin.wfcDefault'.tr,
                          ?w.typeLabel(_locale),
                        ].join(' — '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id == null || id == wf.id) return;
                  _switchTo(workflows.firstWhere((w) => w.id == id));
                },
              ),
            )
          else
            Text(wf.name, style: VfType.sectionTitle.copyWith(color: t.text)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (wf.isDefault)
                AdminBadge('admin.wfcDefault'.tr, tone: VfTone.info),
              AdminBadge(
                wf.isActive ? 'admin.wfcActive'.tr : 'admin.wfcInactive'.tr,
                tone: wf.isActive ? VfTone.ok : VfTone.neutral,
              ),
              AdminBadge('${'admin.wfcAppliesTo'.tr}: $appliesTo'),
              if (_dirty) AdminBadge('admin.wfcUnsaved'.tr, tone: VfTone.warn),
            ],
          ),
          const SizedBox(height: 8),
          AdminSwitch(
            label: 'admin.wfcActive'.tr,
            value: wf.isActive,
            tooltip: wf.isDefault ? 'admin.wfcDefaultAllTypes'.tr : null,
            onChanged: wf.isDefault
                ? null
                : (v) => _patch(() => wf.isActive = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VouchFlowButton(
                label: 'admin.wfcDetails'.tr,
                icon: PhosphorIconsRegular.pencilSimple,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: _openDetails,
              ),
              VouchFlowButton(
                label: 'admin.wfcNewWorkflow'.tr,
                icon: PhosphorIconsRegular.plus,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: _openCreate,
              ),
              VouchFlowButton(
                label: 'admin.presets'.tr,
                icon: PhosphorIconsRegular.magicWand,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: _openPresets,
              ),
              if (!wf.isDefault)
                Tooltip(
                  message: wf.voucherTypeId != null
                      ? 'admin.wfcDefaultAllTypes'.tr
                      : '',
                  child: VouchFlowButton(
                    label: 'admin.wfcMakeDefault'.tr,
                    icon: PhosphorIconsRegular.star,
                    variant: VfButtonVariant.secondary,
                    compact: true,
                    onPressed: _busy || _dirty || wf.voucherTypeId != null
                        ? null
                        : _makeDefault,
                  ),
                ),
              if (!wf.isDefault)
                VouchFlowButton(
                  label: 'admin.delete'.tr,
                  icon: PhosphorIconsRegular.trash,
                  variant: VfButtonVariant.danger,
                  compact: true,
                  onPressed: _openDelete,
                ),
            ],
          ),
          const SizedBox(height: 12),
          VouchFlowButton(
            label: 'admin.saveWorkflow'.tr,
            icon: PhosphorIconsRegular.floppyDisk,
            expand: true,
            loading: _busy,
            onPressed: _busy || !_dirty ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _node(VfTokens t, IconData icon, String label, {bool end = false}) =>
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(VfSize.radiusL),
            border: Border.all(color: t.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: end ? t.success : t.primary,
                  borderRadius: BorderRadius.circular(VfSize.radiusM),
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _flow(VfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _node(t, PhosphorIconsRegular.filePlus, 'admin.voucherRaised'.tr),
        Container(
          margin: const EdgeInsets.only(left: 19),
          padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.borderStrong, width: 1.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                _StepCard(
                  key: ValueKey(_steps[i].uid),
                  step: _steps[i],
                  index: i,
                  count: _steps.length,
                  expanded: _open == i,
                  who: _whoSummary(_steps[i], i),
                  band: _band(_steps[i]),
                  issue: i == 0 ? null : _personIssue(_steps[i]),
                  bandInvalid: _bandInvalid(_steps[i]),
                  people: _people,
                  personLabel: _personLabel,
                  onToggle: () => setState(() => _open = _open == i ? null : i),
                  onChanged: _patch,
                  onMove: (d) => _move(i, d),
                  onRemove: () => _removeStep(i),
                ),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: VouchFlowButton(
                  label: 'admin.addStep'.tr,
                  icon: PhosphorIconsRegular.plus,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  onPressed: _steps.length >= 12 ? null : _addStep,
                ),
              ),
            ],
          ),
        ),
        _node(t, PhosphorIconsRegular.check, 'admin.completed'.tr, end: true),
      ],
    );
  }

  Widget _routingPanel(VfTokens t, Workflow wf) {
    final routing = _routing;
    final stale = _dirty || _routingFor == null || _routingFor!.$1 != wf.id;
    final levelSteps =
        routing?.steps.where((s) => !s.isRequestStep).toList() ??
        const <RoutingStep>[];
    void toDepartments() {
      if (Get.isRegistered<ShellController>()) {
        Get.find<ShellController>().go('/departments');
      }
    }

    return VouchFlowCard(
      title: 'admin.wfcRoutingTitle'.tr,
      subtitle:
          '${'admin.wfcRoutingSub'.tr}${stale && _dirty ? ' ${'admin.wfcRoutingStale'.tr}' : ''}',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowButton(
            label: 'admin.departments'.tr,
            icon: PhosphorIconsRegular.treeStructure,
            variant: VfButtonVariant.secondary,
            compact: true,
            onPressed: toDepartments,
          ),
          const SizedBox(height: 12),
          if (routing == null && _routingFor == null)
            const VouchFlowLoadingState(rows: 3, rowHeight: 56)
          else if (routing != null && routing.departments.isEmpty)
            AdminNote('admin.wfcNoDepartments'.tr)
          else if (routing != null) ...[
            routing.gaps > 0
                ? AdminNote(
                    fill('admin.wfcRoutingGaps'.tr, {'count': routing.gaps}),
                    tone: VfTone.warn,
                  )
                : AdminNote('admin.wfcRoutingNoGaps'.tr),
            const SizedBox(height: 12),
            for (final dept in routing.departments)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(VfSize.radiusL),
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      dept.name,
                      style: VfType.bodyStrong.copyWith(color: t.text),
                    ),
                    const SizedBox(height: 6),
                    for (var i = 0; i < levelSteps.length; i++)
                      _routingRow(
                        t,
                        i,
                        levelSteps[i],
                        dept.cells
                            .where((c) => c.stepId == levelSteps[i].id)
                            .firstOrNull,
                        toDepartments,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _routingRow(
    VfTokens t,
    int i,
    RoutingStep step,
    RoutingCell? cell,
    VoidCallback toDepartments,
  ) {
    Widget value;
    if (cell == null) {
      value = Text('—', style: VfType.small.copyWith(color: t.text));
    } else if (cell.gap != null) {
      value = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AdminBadge((_gapKeys[cell.gap] ?? cell.gap!).tr, tone: VfTone.warn),
          if (_departmentGaps.contains(cell.gap))
            TextButton(
              onPressed: toDepartments,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Text(
                'admin.wfcFixInDepartments'.tr,
                style: VfType.small.copyWith(
                  color: t.primaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      );
    } else {
      final more = cell.people.length - 2;
      value = Text(
        '${cell.people.take(2).join(', ')}${more > 0 ? ' +$more' : ''}',
        textAlign: TextAlign.right,
        style: VfType.small.copyWith(color: t.text),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${'admin.wfcLevel'.tr} ${i + 1}',
                    style: TextStyle(
                      color: t.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' · ${step.label(_locale)}'),
                ],
              ),
              style: VfType.small.copyWith(color: t.muted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(alignment: Alignment.topRight, child: value),
          ),
        ],
      ),
    );
  }

  Widget _matrix(VfTokens t) {
    return VouchFlowCard(
      title: 'admin.permittedHere'.tr,
      subtitle: 'admin.matrixSub'.tr,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: t.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _StepNumber(index: i),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          i == 0 ? 'admin.wfcRequest'.tr : _steps[i].name,
                          style: VfType.bodyStrong.copyWith(color: t.text),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      for (final cap in _caps)
                        _MatrixCheck(
                          label: cap.$2.tr,
                          icon: cap.$3,
                          value: _steps[i].cap(cap.$1),
                          onChanged:
                              i == 0 &&
                                  cap.$1 != 'can_print' &&
                                  cap.$1 != 'can_download'
                              ? null
                              : (v) =>
                                    _patch(() => _steps[i].setCap(cap.$1, v)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.primarySoftStrong,
        borderRadius: BorderRadius.circular(VfSize.radiusM),
      ),
      child: index == 0
          ? Icon(PhosphorIconsRegular.user, size: 14, color: t.primaryText)
          : Text(
              '$index',
              style: VfType.bodyStrong.copyWith(
                color: t.primaryText,
                fontSize: 14,
                height: 1,
              ),
            ),
    );
  }
}

class _MatrixCheck extends StatelessWidget {
  const _MatrixCheck({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(VfSize.radiusM),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
            ),
            Icon(icon, size: 14, color: enabled ? t.muted : t.faint),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.small.copyWith(
                  color: enabled ? t.text2 : t.faint,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// One level of the route: its head (number, name, who acts, thresholds,
/// capabilities) and, when open, everything that can be set on it.
class _StepCard extends StatefulWidget {
  const _StepCard({
    super.key,
    required this.step,
    required this.index,
    required this.count,
    required this.expanded,
    required this.who,
    required this.band,
    required this.issue,
    required this.bandInvalid,
    required this.people,
    required this.personLabel,
    required this.onToggle,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
  });

  final WorkflowStep step;
  final int index, count;
  final bool expanded;
  final String who;
  final String? band, issue;
  final bool bandInvalid;
  final List<DirectoryUser> people;
  final String Function(DirectoryUser) personLabel;
  final VoidCallback onToggle;
  final void Function(VoidCallback) onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  late final _name = TextEditingController(text: widget.step.name);
  late final _nameSw = TextEditingController(text: widget.step.nameSw ?? '');
  late final _min = TextEditingController(text: _fmt(widget.step.minAmount));
  late final _max = TextEditingController(text: _fmt(widget.step.maxAmount));

  static String _fmt(double? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toInt().toString() : '$v');

  static double? _parse(String s) {
    final clean = s.replaceAll(',', '').trim();
    return clean.isEmpty ? null : double.tryParse(clean);
  }

  @override
  void dispose() {
    for (final c in [_name, _nameSw, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = widget.step;
    final request = widget.index == 0;
    final warn = widget.issue != null || widget.bandInvalid;
    final shownCaps = _caps.where(
      (c) => c.$1 != 'can_print' && c.$1 != 'can_download' && s.cap(c.$1),
    );

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: widget.expanded ? t.primaryBorder : t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepNumber(index: widget.index),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          request
                              ? Text(
                                  'admin.wfcRequest'.tr,
                                  style: VfType.bodyStrong.copyWith(
                                    color: t.text,
                                  ),
                                )
                              : Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            '${'admin.wfcLevel'.tr} ${widget.index}',
                                        style: TextStyle(color: t.primaryText),
                                      ),
                                      TextSpan(text: ' · ${s.name}'),
                                    ],
                                  ),
                                  style: VfType.bodyStrong.copyWith(
                                    color: t.text,
                                  ),
                                ),
                          const SizedBox(height: 2),
                          Text(
                            '${'admin.wfcWhoActs'.tr}: ${widget.who}${widget.band == null ? '' : ' · ${widget.band}'}',
                            maxLines: widget.expanded ? 4 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.small.copyWith(color: t.muted),
                          ),
                          if (shownCaps.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final c in shownCaps)
                                  Tooltip(
                                    message: c.$2.tr,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.surface3,
                                        borderRadius: BorderRadius.circular(
                                          VfSize.radiusPill,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(c.$3, size: 13, color: t.text2),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              c.$2.tr,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: VfType.meta.copyWith(
                                                color: t.text2,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (warn)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 4),
                        child: Icon(
                          PhosphorIconsRegular.warning,
                          size: 17,
                          color: t.warningStrong,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4),
                      child: AnimatedRotation(
                        turns: widget.expanded ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          PhosphorIconsRegular.caretDown,
                          size: 17,
                          color: t.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.expanded) _body(t, s, request),
        ],
      ),
    );
  }

  Widget _body(VfTokens t, WorkflowStep s, bool request) {
    const gap = SizedBox(height: 12);
    final assignedMissing =
        s.assignedUserId != null &&
        !widget.people.any((p) => p.id == s.assignedUserId);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowTextField(
            label: 'admin.stepName'.tr,
            controller: _name,
            onChanged: (v) => widget.onChanged(() => s.name = v),
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.wfcNameSw'.tr,
            controller: _nameSw,
            onChanged: (v) =>
                widget.onChanged(() => s.nameSw = v.isEmpty ? null : v),
          ),
          if (!request) ...[
            gap,
            Text(
              'admin.wfcWhoActs'.tr,
              style: VfType.label.copyWith(color: t.text2),
            ),
            const SizedBox(height: 6),
            _Segmented(
              personMode: s.isPersonMode,
              onRole: () => widget.onChanged(() {
                s.assignedUserId = null;
                if (s.role == 'custom') s.role = 'ceo';
              }),
              onPerson: () {
                if (!s.isPersonMode) widget.onChanged(() => s.role = 'custom');
              },
            ),
            gap,
            if (s.isPersonMode)
              _Select<String>(
                key: ValueKey('person|${s.uid}'),
                label: 'admin.wfcChoosePerson'.tr,
                hint: 'admin.wfcPersonHint'.tr,
                value: s.assignedUserId == null ? '' : '${s.assignedUserId}',
                options: [
                  ('', '${'admin.wfcChoosePerson'.tr}…', true),
                  if (assignedMissing)
                    (
                      '${s.assignedUserId}',
                      '${s.assignedUser?.name ?? '—'} (${'admin.wfcInactive'.tr})',
                      false,
                    ),
                  for (final p in widget.people)
                    ('${p.id}', widget.personLabel(p), true),
                ],
                onChanged: (v) => widget.onChanged(
                  () => s.assignedUserId = v.isEmpty ? null : int.parse(v),
                ),
              )
            else
              _Select<String>(
                key: ValueKey('role|${s.uid}'),
                label: 'admin.role'.tr,
                hint: s.role == 'hod' || s.role == 'manager'
                    ? 'admin.wfcDeptHint'.tr
                    : 'admin.wfcRoleHint'.tr,
                value: s.role,
                options: [
                  for (final r in [
                    ..._levelRoles,
                    if (!_levelRoles.contains(s.role)) s.role,
                  ])
                    (
                      r,
                      r == 'hod'
                          ? 'admin.wfcEachHod'.tr
                          : r == 'manager'
                          ? 'admin.wfcEachManager'.tr
                          : wfcRoleName(r),
                      true,
                    ),
                ],
                onChanged: (v) => widget.onChanged(() => s.role = v),
              ),
            if (widget.issue != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      PhosphorIconsRegular.warning,
                      size: 15,
                      color: t.dangerStrong,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.issue!,
                      style: VfType.meta.copyWith(color: t.dangerStrong),
                    ),
                  ),
                ],
              ),
            ],
            gap,
            VouchFlowTextField(
              label: 'admin.fromAmount'.tr,
              controller: _min,
              placeholder: 'admin.anyAmount'.tr,
              hint: 'admin.amountThresholds'.tr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (v) => widget.onChanged(() => s.minAmount = _parse(v)),
            ),
            gap,
            VouchFlowTextField(
              label: 'admin.upToAmount'.tr,
              controller: _max,
              placeholder: 'admin.noCeiling'.tr,
              error: widget.bandInvalid ? 'admin.wfcBandInvalid'.tr : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (v) => widget.onChanged(() => s.maxAmount = _parse(v)),
            ),
          ],
          gap,
          Text(
            'admin.permittedHere'.tr,
            style: VfType.label.copyWith(color: t.text2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cap in _caps)
                _CapToggle(
                  label: cap.$2.tr,
                  icon: cap.$3,
                  on: s.cap(cap.$1),
                  onTap:
                      request &&
                          cap.$1 != 'can_print' &&
                          cap.$1 != 'can_download'
                      ? null
                      : () => widget.onChanged(
                          () => s.setCap(cap.$1, !s.cap(cap.$1)),
                        ),
                ),
            ],
          ),
          if (s.canSign && s.canApprove && !request) ...[
            const SizedBox(height: 6),
            AdminCheck(
              label: 'admin.sigRequired'.tr,
              value: s.requiresSignature,
              onChanged: (v) => widget.onChanged(() => s.requiresSignature = v),
            ),
          ],
          if (s.canSign && !s.canApprove && !request) ...[
            const SizedBox(height: 8),
            Text(
              'admin.signOnlyHint'.tr,
              style: VfType.meta.copyWith(color: t.muted),
            ),
          ],
          if (s.canRequestChanges && !request) ...[
            const SizedBox(height: 8),
            Text(
              'admin.requestChangesHint'.tr,
              style: VfType.meta.copyWith(color: t.muted),
            ),
          ],
          if (!request) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                VouchFlowButton(
                  label: 'admin.moveEarlier'.tr,
                  icon: PhosphorIconsRegular.arrowUp,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: widget.index <= 1 ? null : () => widget.onMove(-1),
                ),
                VouchFlowButton(
                  label: 'admin.moveLater'.tr,
                  icon: PhosphorIconsRegular.arrowDown,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: widget.index >= widget.count - 1
                      ? null
                      : () => widget.onMove(1),
                ),
                VouchFlowButton(
                  label: 'admin.removeStep'.tr,
                  icon: PhosphorIconsRegular.trash,
                  variant: VfButtonVariant.danger,
                  compact: true,
                  onPressed: widget.onRemove,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Role-based or a specific person (the web's `.wfc-seg`).
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.personMode,
    required this.onRole,
    required this.onPerson,
  });

  final bool personMode;
  final VoidCallback onRole, onPerson;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget seg(
      bool selected,
      IconData icon,
      String label,
      VoidCallback onTap,
    ) => Expanded(
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: Material(
          color: selected ? t.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(VfSize.radiusM),
          child: InkWell(
            borderRadius: BorderRadius.circular(VfSize.radiusM),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(VfSize.radiusM),
                      border: Border.all(color: t.primaryBorder),
                    )
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? t.primaryText : t.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: VfType.label.copyWith(
                        color: selected ? t.text : t.muted,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Row(
        children: [
          seg(
            !personMode,
            PhosphorIconsRegular.usersThree,
            'admin.wfcRoleBased'.tr,
            onRole,
          ),
          const SizedBox(width: 3),
          seg(
            personMode,
            PhosphorIconsRegular.userFocus,
            'admin.wfcSpecificPerson'.tr,
            onPerson,
          ),
        ],
      ),
    );
  }
}

/// A capability toggle (the web's `.vf-cap`, aria-pressed).
class _CapToggle extends StatelessWidget {
  const _CapToggle({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final enabled = onTap != null;
    final fg = !enabled ? t.faint : (on ? t.primaryText : t.text2);
    return Semantics(
      toggled: on,
      button: true,
      enabled: enabled,
      child: Material(
        color: on ? t.primarySoft : t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusPill),
          side: BorderSide(color: on ? t.primaryBorder : t.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(on ? PhosphorIconsBold.check : icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.label.copyWith(color: fg, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled select whose options can be disabled (the web's `<option
/// disabled>`), which VouchFlowDropdown does not offer.
class _Select<T> extends StatelessWidget {
  const _Select({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final T value;
  final List<(T, String, bool)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowField(
      label: label,
      hint: hint,
      child: DropdownButtonFormField<T>(
        initialValue: options.any((o) => o.$1 == value) ? value : null,
        isExpanded: true,
        icon: Icon(PhosphorIconsRegular.caretDown, size: 16, color: t.muted),
        dropdownColor: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        style: VfType.body.copyWith(color: t.text),
        decoration: InputDecoration(
          filled: true,
          fillColor: enabled ? t.inputBg : t.inputDisabled,
        ),
        items: [
          for (final o in options)
            DropdownMenuItem<T>(
              value: o.$1,
              enabled: o.$3,
              child: Text(
                o.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: o.$3 ? null : t.faint),
              ),
            ),
        ],
        onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
      ),
    );
  }
}

/// Name, Swahili name, description and voucher-type binding — shared by
/// "Details" and "New workflow".
class _WorkflowFieldsValue {
  _WorkflowFieldsValue({
    this.name = '',
    this.nameSw = '',
    this.description = '',
    this.voucherTypeId,
  });
  String name, nameSw, description;
  int? voucherTypeId;
}

class _WorkflowFields extends StatefulWidget {
  const _WorkflowFields({
    required this.value,
    required this.onChanged,
    required this.types,
    required this.typeName,
    required this.lockType,
    required this.clashes,
  });

  final _WorkflowFieldsValue value;
  final VoidCallback onChanged;
  final List<AdminVoucherType> types;
  final String Function(AdminVoucherType) typeName;
  final bool lockType;

  /// Voucher types another active workflow already routes.
  final List<int> clashes;

  @override
  State<_WorkflowFields> createState() => _WorkflowFieldsState();
}

class _WorkflowFieldsState extends State<_WorkflowFields> {
  late final _name = TextEditingController(text: widget.value.name);
  late final _nameSw = TextEditingController(text: widget.value.nameSw);
  late final _desc = TextEditingController(text: widget.value.description);

  @override
  void dispose() {
    _name.dispose();
    _nameSw.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VouchFlowTextField(
          label: 'admin.wfcNameEn'.tr,
          controller: _name,
          required: true,
          onChanged: (s) {
            v.name = s;
            widget.onChanged();
          },
        ),
        gap,
        VouchFlowTextField(
          label: 'admin.wfcNameSw'.tr,
          controller: _nameSw,
          onChanged: (s) => v.nameSw = s,
        ),
        gap,
        VouchFlowTextField(
          label: 'admin.wfcDescription'.tr,
          controller: _desc,
          maxLength: 255,
          onChanged: (s) => v.description = s,
        ),
        gap,
        _Select<String>(
          label: 'admin.wfcAppliesTo'.tr,
          hint: widget.lockType
              ? 'admin.wfcDefaultAllTypes'.tr
              : 'admin.wfcAppliesToHint'.tr,
          value: v.voucherTypeId == null ? '' : '${v.voucherTypeId}',
          enabled: !widget.lockType,
          options: [
            ('', 'admin.wfcAllTypes'.tr, true),
            for (final type in widget.types.where((x) => x.isActive))
              (
                '${type.id}',
                widget.typeName(type),
                !widget.clashes.contains(type.id) || type.id == v.voucherTypeId,
              ),
          ],
          onChanged: (s) {
            v.voucherTypeId = s.isEmpty ? null : int.parse(s);
            widget.onChanged();
          },
        ),
      ],
    );
  }
}
